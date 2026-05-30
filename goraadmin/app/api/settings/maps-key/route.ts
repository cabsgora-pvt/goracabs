export const dynamic = 'force-dynamic'
import { withCors, corsOptions } from '@/lib/cors'
import { getSettings } from '@/lib/settings'

export async function OPTIONS() { return corsOptions() }

// Exposes only the Maps JS API key for the public /track page.
// Restrict the key in Google Cloud Console by HTTP referrer (goracabs.com/*) to keep this safe.
export async function GET() {
  const s: any = getSettings()
  const key = s?.maps?.javascriptApiKey || s?.maps?.googleMapsApiKey || ''
  return withCors({ key })
}
