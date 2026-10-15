export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { withCors, corsOptions } from '@/lib/cors'
import { getSettings } from '@/lib/settings'
import { isTollStep } from '@/lib/toll-steps'
import { rateLimit } from '@/lib/rate-limit'

export async function OPTIONS() { return corsOptions() }

// Instruction languages the driver app speaks: English and Hindi.
const SUPPORTED_LANGUAGES = new Set(['en', 'hi'])

// GET /api/directions?originLat=..&originLng=..&destLat=..&destLng=..
//   &waypoints=lat,lng|lat,lng      (optional, ordered — for multi-stop legs)
//   &steps=1                        (optional — include turn-by-turn steps)
//   &language=en|hi                 (optional — language of step instructions)
//
// Returns:
//   { polyline, distanceKm, durationMin, status,
//     steps: [{ instruction, maneuver, distanceM, durationSec,
//               startLat, startLng, endLat, endLng, polyline, toll }],
//     legs:  [{ distanceKm, durationMin, endAddress }] }
//
// The steps come back from Google on every Directions call we already make and
// were previously discarded — they are what lets the driver app render real
// turn-by-turn guidance without licensing a Navigation SDK.
function stripHtml(s: string): string {
  return (s || '')
    // Google marks the road name up with <b>, and separates a sub-instruction
    // with a styled <div>. Turn that into a plain sentence.
    .replace(/<div[^>]*>/gi, '. ')
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/\s+/g, ' ')
    .trim()
}

export async function GET(req: NextRequest) {
  try {
    // Public, pre-auth endpoint polled during active rides and turn-by-turn
    // nav — capped per-IP so it can't be scripted into a Google billing spike.
    if (!rateLimit(req, 'directions', 40, 60_000)) {
      return withCors({ error: 'Too many requests, please slow down' }, 429)
    }
    const sp = req.nextUrl.searchParams
    const originLat = parseFloat(sp.get('originLat') || '')
    const originLng = parseFloat(sp.get('originLng') || '')
    const destLat = parseFloat(sp.get('destLat') || '')
    const destLng = parseFloat(sp.get('destLng') || '')
    const wantSteps = sp.get('steps') === '1'
    const waypoints = (sp.get('waypoints') || '').trim()
    // Language of the turn-by-turn instructions, for spoken guidance in the
    // driver's language. Allow-listed, so nothing else reaches Google's URL;
    // omitted, Google answers in English exactly as before.
    const language = SUPPORTED_LANGUAGES.has(sp.get('language') || '') ? sp.get('language') : null

    if ([originLat, originLng, destLat, destLng].some(n => Number.isNaN(n))) {
      return withCors({ error: 'Missing or invalid coords' }, 400)
    }

    const s: any = getSettings()
    const key = s?.maps?.googleMapsApiKey || s?.maps?.javascriptApiKey || ''
    if (!key) return withCors({ error: 'Maps API key not configured' }, 500)

    const url = `https://maps.googleapis.com/maps/api/directions/json` +
      `?origin=${originLat},${originLng}` +
      `&destination=${destLat},${destLng}` +
      (waypoints ? `&waypoints=${encodeURIComponent(waypoints)}` : '') +
      `&mode=driving&departure_time=now&traffic_model=best_guess` +
      (language ? `&language=${language}` : '') +
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
    const legs: any[] = route.legs || []
    const polyline: string = route.overview_polyline?.points || ''

    // Sum across legs so multi-stop chains report the whole journey.
    let distanceMeters = 0
    let durationSeconds = 0
    for (const leg of legs) {
      distanceMeters += leg.distance?.value || 0
      durationSeconds += (leg.duration_in_traffic?.value ?? leg.duration?.value) || 0
    }

    const payload: any = {
      polyline,
      distanceKm: +(distanceMeters / 1000).toFixed(2),
      durationMin: Math.round(durationSeconds / 60),
      status: 'OK',
      legs: legs.map((l: any) => ({
        distanceKm: +((l.distance?.value || 0) / 1000).toFixed(2),
        durationMin: Math.round(((l.duration_in_traffic?.value ?? l.duration?.value) || 0) / 60),
        endAddress: l.end_address || '',
      })),
    }

    if (wantSteps) {
      const steps: any[] = []
      for (const leg of legs) {
        for (const st of (leg.steps || [])) {
          steps.push({
            instruction: stripHtml(st.html_instructions),
            maneuver: st.maneuver || '',           // 'turn-left', 'roundabout-right', …
            distanceM: st.distance?.value || 0,
            durationSec: st.duration?.value || 0,
            startLat: st.start_location?.lat,
            startLng: st.start_location?.lng,
            endLat: st.end_location?.lat,
            endLng: st.end_location?.lng,
            polyline: st.polyline?.points || '',
            // On a toll road, per Google's own note — see lib/toll-steps.ts.
            toll: isTollStep(st.html_instructions),
          })
        }
      }
      payload.steps = steps
    }

    return withCors(payload)
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}
