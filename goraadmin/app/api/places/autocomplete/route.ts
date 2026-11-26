export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { withCors, corsOptions } from '@/lib/cors'
import { getSettingsAsync } from '@/lib/settings'
import { rateLimit } from '@/lib/rate-limit'

export async function OPTIONS() { return corsOptions() }

// Optional bias + billing session (all additive; old app builds send only q):
//   lat, lng      → `location` + `radius` (50 km) so nearby places rank first.
//                   A bias, not strictbounds: an outstation city 300 km away
//                   is still found.
//   sessiontoken  → Google's autocomplete session (one per search, reused for
//                   every keystroke and the final /places/details call).
const BIAS_RADIUS_M = 50_000
const SESSION_RE = /^[A-Za-z0-9_-]{8,64}$/

/** The `location` bias for lat/lng query values, or '' when absent/invalid. */
function biasParam(latRaw: string | null, lngRaw: string | null): string {
  if (latRaw === null || lngRaw === null || latRaw === '' || lngRaw === '') return ''
  const lat = Number(latRaw), lng = Number(lngRaw)
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return ''
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return ''
  if (lat === 0 && lng === 0) return '' // "no fix" sentinel, not a place
  return `&location=${lat.toFixed(6)},${lng.toFixed(6)}&radius=${BIAS_RADIUS_M}`
}

export async function GET(req: NextRequest) {
  try {
    // Public endpoint that bills a paid Google API: capped per IP.
    if (!rateLimit(req, 'places-autocomplete', 60, 60_000)) {
      return withCors({ error: 'Too many requests, please slow down', code: 'RATE_LIMITED' }, 429)
    }
    const sp = req.nextUrl.searchParams
    const q = sp.get('q') || ''
    if (q.length < 2) return withCors({ predictions: [] })
    if (q.length > 200) return withCors({ error: 'Query too long' }, 400)

    const s: any = await getSettingsAsync()
    const key = s?.maps?.googleMapsApiKey || s?.maps?.javascriptApiKey || ''
    if (!key) return withCors({ error: 'Maps API key not configured' }, 500)

    const bias = biasParam(sp.get('lat'), sp.get('lng'))
    const token = sp.get('sessiontoken') || ''
    const session = SESSION_RE.test(token) ? `&sessiontoken=${encodeURIComponent(token)}` : ''

    const url = `https://maps.googleapis.com/maps/api/place/autocomplete/json?input=${encodeURIComponent(q)}&components=country:in${bias}${session}&key=${encodeURIComponent(key)}`
    const r = await fetch(url)
    const data = await r.json()

    // Log + surface Google's error so we can see why suggestions are empty
    if (data.status && data.status !== 'OK' && data.status !== 'ZERO_RESULTS') {
      console.error('[Places Autocomplete] Google error:', data.status, data.error_message)
      return withCors({ predictions: [], googleStatus: data.status, googleError: data.error_message || 'Places API error' })
    }

    // Filter out Plus Code-only predictions (e.g. "JJ4Q+39 Ahmedabad")
    const plusCode = /^[A-Z0-9]{4,8}\+[A-Z0-9]{2,4}\b/i
    const predictions = (data.predictions || [])
      .filter((p: any) => !plusCode.test((p.structured_formatting?.main_text || p.description || '').trim()))
      .map((p: any) => ({
        placeId: p.place_id,
        description: p.description,
        mainText: p.structured_formatting?.main_text || p.description,
        secondaryText: p.structured_formatting?.secondary_text || '',
      }))
    return withCors({ predictions })
  } catch (e: any) {
    return withCors({ error: 'Server error' }, 500)
  }
}
