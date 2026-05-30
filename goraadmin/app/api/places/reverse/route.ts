export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { withCors, corsOptions } from '@/lib/cors'
import { getSettings } from '@/lib/settings'

export async function OPTIONS() { return corsOptions() }

// GET ?lat=..&lng=.. → returns formatted_address for that point
export async function GET(req: NextRequest) {
  try {
    const lat = req.nextUrl.searchParams.get('lat')
    const lng = req.nextUrl.searchParams.get('lng')
    if (!lat || !lng) return withCors({ error: 'lat and lng required' }, 400)

    const s: any = getSettings()
    const key = s?.maps?.googleMapsApiKey || s?.maps?.javascriptApiKey || ''
    if (!key) return withCors({ error: 'Maps API key not configured' }, 500)

    const url = `https://maps.googleapis.com/maps/api/geocode/json?latlng=${lat},${lng}&key=${key}`
    const r = await fetch(url)
    const data = await r.json()

    if (data.status !== 'OK') {
      return withCors({ address: '', googleStatus: data.status, googleError: data.error_message || '' })
    }
    const address = data.results?.[0]?.formatted_address || ''
    return withCors({ address })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
