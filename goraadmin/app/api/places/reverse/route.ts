export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { withCors, corsOptions } from '@/lib/cors'
import { getSettingsAsync } from '@/lib/settings'
import { rateLimit } from '@/lib/rate-limit'
import { pickBestAddress } from '@/lib/geocode'

export async function OPTIONS() { return corsOptions() }

// GET ?lat=..&lng=.. → returns a clean human-readable address (skips Plus Codes)
export async function GET(req: NextRequest) {
  try {
    // Public endpoint that bills a paid Google API: capped per IP.
    if (!rateLimit(req, 'places-reverse', 60, 60_000)) {
      return withCors({ error: 'Too many requests, please slow down' }, 429)
    }
    const lat = req.nextUrl.searchParams.get('lat')
    const lng = req.nextUrl.searchParams.get('lng')
    if (!lat || !lng) return withCors({ error: 'lat and lng required' }, 400)
    const la = Number(lat), ln = Number(lng)
    if (!Number.isFinite(la) || !Number.isFinite(ln) || Math.abs(la) > 90 || Math.abs(ln) > 180) {
      return withCors({ error: 'Invalid lat/lng' }, 400)
    }

    const s: any = await getSettingsAsync()
    const key = s?.maps?.googleMapsApiKey || s?.maps?.javascriptApiKey || ''
    if (!key) return withCors({ error: 'Maps API key not configured' }, 500)

    // Ask Google to exclude plus_code result_type when possible
    const url = `https://maps.googleapis.com/maps/api/geocode/json?latlng=${encodeURIComponent(`${la},${ln}`)}&key=${encodeURIComponent(key)}`
    const r = await fetch(url)
    const data = await r.json()

    if (data.status !== 'OK') {
      return withCors({ address: '', googleStatus: data.status, googleError: data.error_message || '' })
    }
    const address = pickBestAddress(data.results || [])
    return withCors({ address })
  } catch (e: any) {
    return withCors({ error: 'Server error' }, 500)
  }
}
