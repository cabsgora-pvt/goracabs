export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { withCors, corsOptions } from '@/lib/cors'
import { getSettings } from '@/lib/settings'

export async function OPTIONS() { return corsOptions() }

export async function GET(req: NextRequest) {
  try {
    const placeId = req.nextUrl.searchParams.get('placeId') || ''
    if (!placeId) return withCors({ error: 'placeId required' }, 400)

    const s: any = getSettings()
    const key = s?.maps?.googleMapsApiKey || s?.maps?.javascriptApiKey || ''
    if (!key) return withCors({ error: 'Maps API key not configured' }, 500)

    const url = `https://maps.googleapis.com/maps/api/place/details/json?place_id=${placeId}&fields=geometry,formatted_address,name&key=${key}`
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
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
