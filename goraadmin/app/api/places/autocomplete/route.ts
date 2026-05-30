export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { withCors, corsOptions } from '@/lib/cors'
import { getSettings } from '@/lib/settings'

export async function OPTIONS() { return corsOptions() }

export async function GET(req: NextRequest) {
  try {
    const q = req.nextUrl.searchParams.get('q') || ''
    if (q.length < 2) return withCors({ predictions: [] })

    const s: any = getSettings()
    const key = s?.maps?.googleMapsApiKey || s?.maps?.javascriptApiKey || ''
    if (!key) return withCors({ error: 'Maps API key not configured' }, 500)

    const url = `https://maps.googleapis.com/maps/api/place/autocomplete/json?input=${encodeURIComponent(q)}&components=country:in&key=${key}`
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
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
