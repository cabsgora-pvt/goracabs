export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { withCors, corsOptions } from '@/lib/cors'
import { getSettingsAsync } from '@/lib/settings'
import { rateLimit } from '@/lib/rate-limit'
import { detailsNew, legacyUnusable } from '@/lib/places-new'

export async function OPTIONS() { return corsOptions() }

export async function GET(req: NextRequest) {
  try {
    // Public endpoint that bills a paid Google API: capped per IP.
    if (!rateLimit(req, 'places-details', 60, 60_000)) {
      return withCors({ error: 'Too many requests, please slow down', code: 'RATE_LIMITED' }, 429)
    }
    const placeId = req.nextUrl.searchParams.get('placeId') || ''
    if (!placeId) return withCors({ error: 'placeId required' }, 400)
    if (placeId.length > 300) return withCors({ error: 'Invalid placeId' }, 400)

    const s: any = await getSettingsAsync()
    const key = s?.maps?.googleMapsApiKey || s?.maps?.javascriptApiKey || ''
    if (!key) return withCors({ error: 'Maps API key not configured' }, 500)

    // Optional: the autocomplete session this pick ends (additive; see
    // /api/places/autocomplete). Google bills the session as one.
    const token = req.nextUrl.searchParams.get('sessiontoken') || ''
    const session = /^[A-Za-z0-9_-]{8,64}$/.test(token) ? `&sessiontoken=${encodeURIComponent(token)}` : ''
    const url = `https://maps.googleapis.com/maps/api/place/details/json?place_id=${encodeURIComponent(placeId)}&fields=geometry,formatted_address,name${session}&key=${encodeURIComponent(key)}`
    const r = await fetch(url)
    const data = await r.json()
    const result = data.result

    if (!result) {
      // Legacy Places not enabled on this key (or a Places (New) id): ask (New).
      if (legacyUnusable(data.status) || data.status === 'NOT_FOUND') {
        const alt = await detailsNew(placeId, key, /^[A-Za-z0-9_-]{8,64}$/.test(token) ? token : undefined)
        if (alt) return withCors(alt)
      }
      return withCors({ error: 'Place not found' }, 404)
    }

    return withCors({
      address: result.formatted_address || result.name || '',
      lat: result.geometry?.location?.lat,
      lng: result.geometry?.location?.lng,
    })
  } catch (e: any) {
    return withCors({ error: 'Server error' }, 500)
  }
}
