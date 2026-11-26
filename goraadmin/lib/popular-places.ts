// Popular places near a rider (stations, airport, malls, tourist spots) for the
// rider app's home screen — like the "places near you" row in ride apps.
//
// Cost control: the world is cut into 0.1° cells (~11 km); each cell is fetched
// from Google Places (Nearby Search, one call per category) at most once per
// CACHE_DAYS and kept in Mongo, so a whole city costs ~5 calls a week. Photo
// URLs are resolved once on the server (Google redirects the photo request to a
// key-less googleusercontent URL), so the API key never reaches the app.

export const POPULAR = {
  CELL_DEG: 0.1,
  RADIUS_M: 15_000,
  // A small town has few famous places within 15 km: search wider (the
  // nearest city's station, fort, temple) when the first pass finds fewer than MIN_PLACES.
  WIDE_RADIUS_M: 40_000,
  MIN_PLACES: 6,
  CACHE_DAYS: 7,
  EMPTY_RETRY_HOURS: 6,   // a failed / empty fetch is retried sooner
  PHOTO_W: 480,
  MAX: 12,
}

/** Categories, in the order the rider sees them, with how many of each to keep. */
export const CATEGORIES: { type: string; label: string; keep: number }[] = [
  { type: 'train_station', label: 'Station', keep: 2 },
  { type: 'airport', label: 'Airport', keep: 1 },
  { type: 'bus_station', label: 'Bus stand', keep: 1 },
  { type: 'shopping_mall', label: 'Mall', keep: 3 },
  { type: 'tourist_attraction', label: 'Tourist place', keep: 6 },
]

export type PopularPlace = {
  id: string
  name: string
  category: string        // label shown on the chip
  type: string            // Google type
  address: string
  lat: number
  lng: number
  rating: number | null
  ratings: number
  photoUrl: string | null
}

export function cellOf(lat: number, lng: number): { key: string; lat: number; lng: number } {
  const r = (v: number) => Math.round(v / POPULAR.CELL_DEG) * POPULAR.CELL_DEG
  const cl = Number(r(lat).toFixed(1)), cg = Number(r(lng).toFixed(1))
  return { key: `${cl.toFixed(1)},${cg.toFixed(1)}`, lat: cl, lng: cg }
}

export function distanceKm(aLat: number, aLng: number, bLat: number, bLng: number): number {
  const R = 6371, rad = Math.PI / 180
  const dLat = (bLat - aLat) * rad, dLng = (bLng - aLng) * rad
  const x = Math.sin(dLat / 2) ** 2 + Math.cos(aLat * rad) * Math.cos(bLat * rad) * Math.sin(dLng / 2) ** 2
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(x)))
}

/** Popularity: rating weighted by how many people rated it. */
export function score(p: { rating?: number | null; ratings?: number }): number {
  const r = Number(p.rating) || 0, n = Number(p.ratings) || 0
  return r * Math.log10(n + 10)
}

// Google results we never want as a "place to go": lodging/hospitals that
// Google also tags as tourist attractions, and places that are shut down.
function usable(g: any): boolean {
  if (g?.business_status && g.business_status !== 'OPERATIONAL') return false
  const types: string[] = g?.types || []
  if (types.includes('lodging') || types.includes('hospital') || types.includes('doctor')) return false
  if (!g?.geometry?.location || !g?.name) return false
  return (Number(g.user_ratings_total) || 0) >= 20
}

/** Turns Google's photo request into the key-less image URL it redirects to. */
export async function resolvePhotoUrl(ref: string, key: string, fetchImpl: typeof fetch = fetch): Promise<string | null> {
  if (!ref) return null
  try {
    const u = `https://maps.googleapis.com/maps/api/place/photo?maxwidth=${POPULAR.PHOTO_W}&photo_reference=${encodeURIComponent(ref)}&key=${encodeURIComponent(key)}`
    const r = await fetchImpl(u, { redirect: 'manual' } as any)
    const loc = r.headers.get('location')
    if (loc && /^https:\/\//.test(loc) && !loc.includes('key=')) return loc
  } catch {}
  return null
}

// ── Places API (New) — the primary source (the local key allows only this) ──
const NEW_FIELDS = 'places.id,places.primaryType,places.displayName,places.shortFormattedAddress,places.formattedAddress,places.location,places.rating,places.userRatingCount,places.photos,places.businessStatus,places.types'

// What each category must really BE (Google's primaryType). Nearby Search by
// type also returns shops that merely carry the tag ("Bike Rental" as an
// airport, a clothing store as a mall). Tourist places stay loose: a famous
// fort, temple or park is primarily that, and tagged tourist_attraction.
const PRIMARY_OK: Record<string, string[]> = {
  train_station: ['train_station', 'transit_station', 'subway_station', 'light_rail_station'],
  airport: ['airport', 'international_airport'],
  bus_station: ['bus_station', 'transit_station', 'transit_depot'],
  shopping_mall: ['shopping_mall'],
}

export function categoryMatches(type: string, primaryType: any): boolean {
  const ok = PRIMARY_OK[type]
  return !ok || ok.includes(String(primaryType || ''))
}

function usableNew(g: any): boolean {
  if (g?.businessStatus && g.businessStatus !== 'OPERATIONAL') return false
  const types: string[] = g?.types || []
  if (types.includes('lodging') || types.includes('hospital') || types.includes('doctor')) return false
  if (!g?.location || !g?.displayName?.text) return false
  return (Number(g.userRatingCount) || 0) >= 20
}

/** Key-less image URL for a Places (New) photo name. */
export async function resolvePhotoNew(name: string, key: string, fetchImpl: typeof fetch = fetch): Promise<string | null> {
  if (!name || !/^places\/[^/]+\/photos\/[^/]+$/.test(name)) return null
  try {
    const r = await fetchImpl(`https://places.googleapis.com/v1/${name}/media?maxWidthPx=${POPULAR.PHOTO_W}&skipHttpRedirect=true&key=${encodeURIComponent(key)}`)
    const j: any = await r.json()
    const u = j?.photoUri
    if (typeof u === 'string' && /^https:\/\//.test(u) && !u.includes('key=')) return u
  } catch {}
  return null
}

async function fetchPopularNew(cellLat: number, cellLng: number, key: string, fetchImpl: typeof fetch, radiusM: number = POPULAR.RADIUS_M): Promise<{ places: PopularPlace[]; status: string }> {
  const seen = new Set<string>()
  const out: PopularPlace[] = []
  let status = 'OK'
  for (const c of CATEGORIES) {
    let data: any = {}
    try {
      const r = await fetchImpl('https://places.googleapis.com/v1/places:searchNearby', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Goog-Api-Key': key, 'X-Goog-FieldMask': NEW_FIELDS },
        body: JSON.stringify({
          includedTypes: [c.type],
          maxResultCount: 10,
          rankPreference: 'POPULARITY',
          locationRestriction: { circle: { center: { latitude: cellLat, longitude: cellLng }, radius: radiusM } },
        }),
      } as any)
      data = await r.json()
      if (!r.ok) { status = String(data?.error?.status || r.status); continue }
    } catch { status = 'FETCH_FAILED'; continue }
    const picked = (data.places || [])
      .filter(usableNew)
      .filter((g: any) => categoryMatches(c.type, g.primaryType))
      .filter((g: any) => !seen.has(g.id))
      .map((g: any) => ({ g, s: score({ rating: g.rating, ratings: g.userRatingCount }) }))
      .sort((a: any, b: any) => b.s - a.s)
      .slice(0, c.keep)
    for (const { g } of picked) {
      seen.add(g.id)
      out.push({
        id: String(g.id),
        name: String(g.displayName.text).slice(0, 80),
        category: c.label,
        type: c.type,
        address: String(g.shortFormattedAddress || g.formattedAddress || '').slice(0, 160),
        lat: Number(g.location.latitude),
        lng: Number(g.location.longitude),
        rating: typeof g.rating === 'number' ? g.rating : null,
        ratings: Number(g.userRatingCount) || 0,
        photoUrl: await resolvePhotoNew(g.photos?.[0]?.name || '', key, fetchImpl),
      })
    }
  }
  return { places: out.slice(0, POPULAR.MAX), status }
}

/** Google often lists one place twice ("Dehradun Train Station" and "Dehradun
 *  Railway Station"): within one category, a place 400 m or less from one
 *  already kept is the same place. The list is in popularity order, so the
 *  better-known entry stays. */
export function dropNearDuplicates(places: PopularPlace[]): PopularPlace[] {
  const kept: PopularPlace[] = []
  // A "tourist place" that is really a station / airport / bus stand is
  // transport, already in its own category.
  const transport = /\b(railway|station|junction|airport|bus ?stand|isbt|depot)\b/i
  for (const p of places) {
    if (p.type === 'tourist_attraction' && transport.test(p.name)) continue
    if (kept.some(k => k.category === p.category && distanceKm(k.lat, k.lng, p.lat, p.lng) <= 0.4)) continue
    kept.push(p)
  }
  return kept
}

/** One fetch at one radius: Places API (New) first, the legacy API if that fails. */
async function fetchAt(cellLat: number, cellLng: number, key: string, fetchImpl: typeof fetch, radiusM: number) {
  const n = await fetchPopularNew(cellLat, cellLng, key, fetchImpl, radiusM)
  if (n.places.length) return n
  const l = await fetchPopularLegacy(cellLat, cellLng, key, fetchImpl, radiusM)
  return l.places.length ? l : { places: [] as PopularPlace[], status: `new:${n.status} legacy:${l.status}` }
}

/** A fresh list for a cell: 15 km first; a town with fewer than MIN_PLACES
 *  famous places within that is searched again at 40 km (the extra places are
 *  added after the near ones). `radiusKm` says how far the list reaches. */
export async function fetchPopular(cellLat: number, cellLng: number, key: string, fetchImpl: typeof fetch = fetch): Promise<{ places: PopularPlace[]; status: string; radiusKm: number }> {
  const near = await fetchAt(cellLat, cellLng, key, fetchImpl, POPULAR.RADIUS_M)
  near.places = dropNearDuplicates(near.places)
  if (near.places.length >= POPULAR.MIN_PLACES) return { ...near, radiusKm: POPULAR.RADIUS_M / 1000 }
  const wide = await fetchAt(cellLat, cellLng, key, fetchImpl, POPULAR.WIDE_RADIUS_M)
  const seen = new Set(near.places.map(p => p.id))
  const places = dropNearDuplicates([...near.places, ...wide.places.filter(p => !seen.has(p.id))]).slice(0, POPULAR.MAX)
  return { places, status: places.length ? 'OK' : wide.status, radiusKm: POPULAR.WIDE_RADIUS_M / 1000 }
}

/** Legacy Places (Nearby Search) — fallback. */
async function fetchPopularLegacy(cellLat: number, cellLng: number, key: string, fetchImpl: typeof fetch = fetch, radiusM: number = POPULAR.RADIUS_M): Promise<{ places: PopularPlace[]; status: string }> {  const seen = new Set<string>()
  const out: PopularPlace[] = []
  let status = 'OK'
  for (const c of CATEGORIES) {
    const url = `https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=${cellLat},${cellLng}&radius=${radiusM}&type=${c.type}&key=${encodeURIComponent(key)}`
    let data: any = {}
    try { data = await (await fetchImpl(url)).json() } catch { status = 'FETCH_FAILED'; continue }
    if (data.status && data.status !== 'OK' && data.status !== 'ZERO_RESULTS') { status = data.status; continue }
    const picked = (data.results || [])
      .filter(usable)
      .filter((g: any) => !seen.has(g.place_id))
      .map((g: any) => ({ g, s: score({ rating: g.rating, ratings: g.user_ratings_total }) }))
      .sort((a: any, b: any) => b.s - a.s)
      .slice(0, c.keep)
    for (const { g } of picked) {
      seen.add(g.place_id)
      out.push({
        id: String(g.place_id),
        name: String(g.name).slice(0, 80),
        category: c.label,
        type: c.type,
        address: String(g.vicinity || g.formatted_address || '').slice(0, 160),
        lat: Number(g.geometry.location.lat),
        lng: Number(g.geometry.location.lng),
        rating: typeof g.rating === 'number' ? g.rating : null,
        ratings: Number(g.user_ratings_total) || 0,
        photoUrl: await resolvePhotoUrl(g.photos?.[0]?.photo_reference || '', key, fetchImpl),
      })
    }
  }
  return { places: out.slice(0, POPULAR.MAX), status }
}
