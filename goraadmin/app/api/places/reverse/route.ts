export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { withCors, corsOptions } from '@/lib/cors'
import { getSettings } from '@/lib/settings'

export async function OPTIONS() { return corsOptions() }

// Plus Codes look like "JJ4Q+39 Some Area" — skip these in favour of a real street/area name.
const PLUS_CODE_RE = /^[A-Z0-9]{4,8}\+[A-Z0-9]{2,4}\b/i

// Result types ranked by how readable they are to a human (best first)
const PREFERRED_TYPES = [
  'street_address', 'premise', 'subpremise', 'establishment',
  'point_of_interest', 'route', 'neighborhood',
  'sublocality', 'sublocality_level_1', 'sublocality_level_2',
  'locality', 'administrative_area_level_2', 'administrative_area_level_1',
]

function pickBestAddress(results: any[]): string {
  if (!Array.isArray(results) || results.length === 0) return ''

  // First pass: try preferred types in order — return the first result that has any of them AND isn't a Plus Code
  for (const type of PREFERRED_TYPES) {
    for (const r of results) {
      if (!r.types?.includes(type)) continue
      const addr = (r.formatted_address || '').trim()
      if (!addr) continue
      if (PLUS_CODE_RE.test(addr)) continue
      return addr
    }
  }

  // Second pass: any result whose formatted_address isn't a Plus Code
  for (const r of results) {
    const addr = (r.formatted_address || '').trim()
    if (addr && !PLUS_CODE_RE.test(addr)) return addr
  }

  // Last resort: strip the Plus Code prefix from the first result if everything is a Plus Code
  const fallback = (results[0]?.formatted_address || '').trim()
  return fallback.replace(PLUS_CODE_RE, '').replace(/^[\s,]+/, '').trim() || fallback
}

// GET ?lat=..&lng=.. → returns a clean human-readable address (skips Plus Codes)
export async function GET(req: NextRequest) {
  try {
    const lat = req.nextUrl.searchParams.get('lat')
    const lng = req.nextUrl.searchParams.get('lng')
    if (!lat || !lng) return withCors({ error: 'lat and lng required' }, 400)

    const s: any = getSettings()
    const key = s?.maps?.googleMapsApiKey || s?.maps?.javascriptApiKey || ''
    if (!key) return withCors({ error: 'Maps API key not configured' }, 500)

    // Ask Google to exclude plus_code result_type when possible
    const url = `https://maps.googleapis.com/maps/api/geocode/json?latlng=${lat},${lng}&key=${key}`
    const r = await fetch(url)
    const data = await r.json()

    if (data.status !== 'OK') {
      return withCors({ address: '', googleStatus: data.status, googleError: data.error_message || '' })
    }
    const address = pickBestAddress(data.results || [])
    return withCors({ address })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
