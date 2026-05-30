export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { withCors, corsOptions } from '@/lib/cors'
import { getSettings } from '@/lib/settings'

export async function OPTIONS() { return corsOptions() }

// GET /api/directions?originLat=..&originLng=..&destLat=..&destLng=..
// Returns:
//   { polyline: "encoded string", distanceKm: 5.2, durationMin: 12, status: "OK" }
// The polyline is Google's encoded polyline (Algorithm).
// Caller (Flutter) decodes via google_polyline_algorithm or similar package.
export async function GET(req: NextRequest) {
  try {
    const sp = req.nextUrl.searchParams
    const originLat = parseFloat(sp.get('originLat') || '')
    const originLng = parseFloat(sp.get('originLng') || '')
    const destLat = parseFloat(sp.get('destLat') || '')
    const destLng = parseFloat(sp.get('destLng') || '')

    if ([originLat, originLng, destLat, destLng].some(n => Number.isNaN(n))) {
      return withCors({ error: 'Missing or invalid coords' }, 400)
    }

    const s: any = getSettings()
    const key = s?.maps?.googleMapsApiKey || s?.maps?.javascriptApiKey || ''
    if (!key) return withCors({ error: 'Maps API key not configured' }, 500)

    const url = `https://maps.googleapis.com/maps/api/directions/json` +
      `?origin=${originLat},${originLng}` +
      `&destination=${destLat},${destLng}` +
      `&mode=driving&departure_time=now&traffic_model=best_guess` +
      `&key=${key}`

    const r = await fetch(url)
    const data = await r.json()

    if (data.status !== 'OK' || !data.routes?.length) {
      console.error('[Directions] Google error:', data.status, data.error_message)
      return withCors({
        error: 'No route found',
        googleStatus: data.status,
        googleError: data.error_message || null,
      }, 200)
    }

    const route = data.routes[0]
    const leg = route.legs?.[0] || {}
    const polyline: string = route.overview_polyline?.points || ''
    const distanceMeters: number = leg.distance?.value || 0
    const durationSeconds: number = (leg.duration_in_traffic?.value ?? leg.duration?.value) || 0

    return withCors({
      polyline,
      distanceKm: +(distanceMeters / 1000).toFixed(2),
      durationMin: Math.round(durationSeconds / 60),
      status: 'OK',
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
