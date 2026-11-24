export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { withCors, corsOptions } from '@/lib/cors'
import { getSettingsAsync } from '@/lib/settings'
import { rateLimit } from '@/lib/rate-limit'

export async function OPTIONS() { return corsOptions() }

export async function GET(req: NextRequest) {
  try {
    // Public endpoint that bills a paid Google API: capped per IP.
    if (!rateLimit(req, 'places-details', 60, 60_000)) {
      return withCors({ error: 'Too many requests, please slow down' }, 429)
    }
    const placeId = req.nextUrl.searchParams.get('placeId') || ''
    if (!placeId) return withCors({ error: 'placeId required' }, 400)
    if (placeId.length > 300) return withCors({ error: 'Invalid placeId' }, 400)

    const s: any = await getSettingsAsync()
    const key = s?.maps?.googleMapsApiKey || s?.maps?.javascriptApiKey || ''
    if (!key) return withCors({ error: 'Maps API key not configured' }, 500)

    const url = `https://maps.googleapis.com/maps/api/place/details/json?place_id=${encodeURIComponent(placeId)}&fields=geometry,formatted_address,name&key=${encodeURIComponent(key)}`
    const r = await fetch(url)
    const data = await r.json()
    const result = data.result

    if (!result) return withCors({ error: 'Place not found' }, 404)

    return withCors({
      address: result.formatted_address || result.name || '',
      lat: result.geometry?.location?.lat,
      lng: result.geometry?.location?.lng,
    })
  } catch (e: any) {
    return withCors({ error: 'Server error' }, 500)
  }
}
