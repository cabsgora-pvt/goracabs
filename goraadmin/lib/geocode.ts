import { getSettings } from '@/lib/settings'

// ─────────────────────────────────────────────────────────────────────────────
// Coordinates → a readable address, shared by /api/places/reverse and the
// outstation toll entries (so a toll on the bill says where it was paid).
// Moved here unchanged from the reverse route.
// ─────────────────────────────────────────────────────────────────────────────

// Plus Codes look like "JJ4Q+39 Some Area" — skip these in favour of a real street/area name.
const PLUS_CODE_RE = /^[A-Z0-9]{4,8}\+[A-Z0-9]{2,4}\b/i

// Result types ranked by how readable they are to a human (best first)
const PREFERRED_TYPES = [
  'street_address', 'premise', 'subpremise', 'establishment',
  'point_of_interest', 'route', 'neighborhood',
  'sublocality', 'sublocality_level_1', 'sublocality_level_2',
  'locality', 'administrative_area_level_2', 'administrative_area_level_1',
]

export function pickBestAddress(results: any[]): string {
  if (!Array.isArray(results) || results.length === 0) return ''

  // First pass: try preferred types in order — return the first result that has any of them AND isn't a Plus Code
  for (const type of PREFERRED_TYPES) {
    for (const r of results) {
      if (!r.types?.includes(type)) continue
      const addr = (r.formatted_address || '').trim()
      if (!addr) continue
      if (PLUS_CODE_RE.test(addr)) continue
      return addr
    }
  }

  // Second pass: any result whose formatted_address isn't a Plus Code
  for (const r of results) {
    const addr = (r.formatted_address || '').trim()
    if (addr && !PLUS_CODE_RE.test(addr)) return addr
  }

  // Last resort: strip the Plus Code prefix from the first result if everything is a Plus Code
  const fallback = (results[0]?.formatted_address || '').trim()
  return fallback.replace(PLUS_CODE_RE, '').replace(/^[\s,]+/, '').trim() || fallback
}

/**
 * The address at [lat],[lng], or '' when there is no key, no result, or Google
 * does not answer within [timeoutMs]. Never throws: callers use it to annotate,
 * and a missing address must never stop the thing being annotated.
 */
export async function reverseGeocode(lat: number, lng: number, timeoutMs = 3000): Promise<string> {
  try {
    const s: any = getSettings()
    const key = s?.maps?.googleMapsApiKey || s?.maps?.javascriptApiKey || ''
    if (!key || !Number.isFinite(lat) || !Number.isFinite(lng)) return ''
    const ctrl = new AbortController()
    const timer = setTimeout(() => ctrl.abort(), timeoutMs)
    try {
      const r = await fetch(`https://maps.googleapis.com/maps/api/geocode/json?latlng=${lat},${lng}&key=${key}`, { signal: ctrl.signal })
      const data = await r.json()
      return data?.status === 'OK' ? pickBestAddress(data.results || []) : ''
    } finally {
      clearTimeout(timer)
    }
  } catch {
    return ''
  }
}
