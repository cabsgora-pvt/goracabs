// Places API (New) fallbacks for the legacy Places endpoints.
//
// Google stopped enabling the legacy Places API for new projects (keys made
// since 2025 often allow only Places API (New)). When the legacy call is
// denied, the autocomplete / details routes answer through these instead, in
// the exact shape the apps already read — so search keeps working whichever
// key the admin pastes in.

export type Prediction = { placeId: string; description: string; mainText: string; secondaryText: string }

/** Legacy statuses that mean "this key / API cannot be used", worth a retry on (New). */
export function legacyUnusable(status: any): boolean {
  return status === 'REQUEST_DENIED' || status === 'OVER_QUERY_LIMIT' || status === 'INVALID_REQUEST'
}

export async function autocompleteNew(
  input: string, key: string,
  opts: { lat?: number; lng?: number; radiusM?: number; sessionToken?: string } = {},
  fetchImpl: typeof fetch = fetch,
): Promise<{ ok: boolean; predictions: Prediction[]; error?: string }> {
  try {
    const body: any = { input, includedRegionCodes: ['in'], languageCode: 'en' }
    if (Number.isFinite(opts.lat) && Number.isFinite(opts.lng)) {
      body.locationBias = { circle: { center: { latitude: opts.lat, longitude: opts.lng }, radius: Math.min(opts.radiusM || 50_000, 50_000) } }
    }
    if (opts.sessionToken) body.sessionToken = opts.sessionToken
    const r = await fetchImpl('https://places.googleapis.com/v1/places:autocomplete', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Goog-Api-Key': key },
      body: JSON.stringify(body),
    } as any)
    const j: any = await r.json()
    if (!r.ok) return { ok: false, predictions: [], error: j?.error?.message || `HTTP ${r.status}` }
    const predictions: Prediction[] = (j.suggestions || [])
      .map((s: any) => s.placePrediction)
      .filter((p: any) => p?.placeId)
      .map((p: any) => ({
        placeId: String(p.placeId),
        description: p.text?.text || '',
        mainText: p.structuredFormat?.mainText?.text || p.text?.text || '',
        secondaryText: p.structuredFormat?.secondaryText?.text || '',
      }))
    return { ok: true, predictions }
  } catch (e: any) {
    return { ok: false, predictions: [], error: e?.message || 'fetch failed' }
  }
}

export async function detailsNew(
  placeId: string, key: string, sessionToken?: string, fetchImpl: typeof fetch = fetch,
): Promise<{ address: string; lat: number; lng: number } | null> {
  try {
    const qs = sessionToken ? `?sessionToken=${encodeURIComponent(sessionToken)}` : ''
    const r = await fetchImpl(`https://places.googleapis.com/v1/places/${encodeURIComponent(placeId)}${qs}`, {
      headers: { 'X-Goog-Api-Key': key, 'X-Goog-FieldMask': 'location,formattedAddress,displayName' },
    } as any)
    const j: any = await r.json()
    if (!r.ok || !j?.location) return null
    const name = j.displayName?.text || ''
    const addr = j.formattedAddress || ''
    return {
      // "Jubilee Garden, Rajkot, Gujarat…" — keep the place's own name in front.
      address: name && addr && !addr.startsWith(name) ? `${name}, ${addr}` : (addr || name),
      lat: Number(j.location.latitude),
      lng: Number(j.location.longitude),
    }
  } catch {
    return null
  }
}
