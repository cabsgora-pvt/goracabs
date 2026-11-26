export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import { withCors, corsOptions } from '@/lib/cors'
import { getSettingsAsync } from '@/lib/settings'
import { rateLimitAsync } from '@/lib/rate-limit'
import PopularPlacesCache from '@/models/PopularPlacesCache'
import { POPULAR, cellOf, distanceKm, fetchPopular } from '@/lib/popular-places'

export async function OPTIONS() { return corsOptions() }

// One Google fetch per cell at a time in this process (a cold cell opened by
// many riders at once must not cost one fetch each).
const inflight = new Map<string, Promise<any>>()

// GET /api/places/popular?lat&lng → { places: [{ id, name, category, type,
//   address, lat, lng, rating, ratings, photoUrl, distanceKm }], cached }
// Rider home "Popular places near you": stations, airport, bus stand, malls and
// tourist spots around the rider, nearest of the popular ones first.
// Public (shown before sign-in too), rate-limited, served from a per-cell
// cache — Google is called only when a cell is new or older than a week.
export async function GET(req: NextRequest) {
  try {
    if (!(await rateLimitAsync(req, 'places-popular', 30, 60_000))) {
      return withCors({ places: [], error: 'Too many requests', code: 'RATE_LIMITED' }, 429)
    }
    const sp = req.nextUrl.searchParams
    const lat = Number(sp.get('lat')), lng = Number(sp.get('lng'))
    if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180 || (lat === 0 && lng === 0)) {
      return withCors({ places: [] })
    }
    // India only (the service area); anything else gets an empty list, no Google call.
    if (lat < 6 || lat > 37.5 || lng < 68 || lng > 97.5) return withCors({ places: [] })

    await connectDB()
    const cell = cellOf(lat, lng)
    const cached: any = await PopularPlacesCache.findOne({ cell: cell.key }).lean()
    const ageMs = cached ? Date.now() - new Date(cached.fetchedAt).getTime() : Infinity
    const fresh = cached && (cached.places?.length
      ? ageMs < POPULAR.CACHE_DAYS * 86_400_000
      : ageMs < POPULAR.EMPTY_RETRY_HOURS * 3_600_000)

    let places: any[] = cached?.places || []
    let fromCache = !!fresh
    let reachKm: number = cached?.radiusKm || 15
    if (!fresh) {
      const s: any = await getSettingsAsync()
      const key = s?.maps?.googleMapsApiKey || s?.maps?.javascriptApiKey || ''
      if (key) {
        let job = inflight.get(cell.key)
        if (!job) {
          job = fetchPopular(cell.lat, cell.lng, key).finally(() => inflight.delete(cell.key))
          inflight.set(cell.key, job)
        }
        const got = await job
        // Keep the old list when Google failed and returned nothing new.
        if (got.places.length || !places.length) { places = got.places; reachKm = got.radiusKm }
        await PopularPlacesCache.updateOne(
          { cell: cell.key },
          { $set: { places, fetchedAt: new Date(), googleStatus: got.status, radiusKm: got.radiusKm } },
          { upsert: true },
        )
        if (got.status !== 'OK') console.error('[places/popular] Google status', got.status, 'cell', cell.key)
      }
    }

    const out = places
      .map((p: any) => ({ ...p, distanceKm: Math.round(distanceKm(lat, lng, p.lat, p.lng) * 10) / 10 }))
      // The cell is ~11 km wide, so allow its reach plus that.
      .filter((p: any) => p.distanceKm <= reachKm + 15)
      .sort((a: any, b: any) => a.distanceKm - b.distanceKm)
    return withCors({ places: out, cached: fromCache })
  } catch (e: any) {
    console.error('[places/popular]', e?.message)
    return withCors({ places: [], error: 'Server error' }, 500)
  }
}
