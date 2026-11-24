export const dynamic = 'force-dynamic'
import { withCors, corsOptions } from '@/lib/cors'
import { getSettingsAsync } from '@/lib/settings'

export async function OPTIONS() { return corsOptions() }

// Exposes only the browser Maps JS API key for the public /track page. It must
// NEVER fall back to the server key (googleMapsApiKey): that key is unrestricted
// by referrer and would let anyone bill Places/Directions to us. Restrict the JS
// key in Google Cloud Console by HTTP referrer (goracabs.com/*).
export async function GET() {
  const s: any = await getSettingsAsync().catch(() => ({}))
  const key = s?.maps?.javascriptApiKey || ''
  return withCors({ key })
}
