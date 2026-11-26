import { NextRequest, NextResponse } from 'next/server'

// List of dashboard paths that require admin auth
const DASHBOARD_PATHS = [
  '/dashboard', '/users', '/drivers', '/vehicles', '/services',
  '/zones', '/rides', '/finance', '/fleet', '/promos',
  '/support', '/notifications', '/banners', '/settings', '/zone-admins', '/zone-plans', '/zone-invoice',
  '/account-requests', '/document-types', '/ride-preferences', '/audit-log', '/review',
]

// CORS allow-list. The rider/driver apps are native (no Origin header) and the
// dashboard is same-origin, so only these browser origins may read responses
// with credentials. Any other Origin gets no Access-Control-Allow-* headers.
const ALLOWED_ORIGINS = new Set([
  'https://goracabs.com',
  'https://www.goracabs.com',
  'http://localhost:3000',
])

function corsHeaders(origin: string | null): Record<string, string> {
  if (!origin || !ALLOWED_ORIGINS.has(origin)) return { Vary: 'Origin' }
  return {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization, x-admin-password, x-admin-override',
    'Access-Control-Allow-Credentials': 'true',
    Vary: 'Origin',
  }
}

// ── CSRF for cookie-authenticated API calls ──
// The dashboard, the zone panel and the driver web flow authenticate with
// cookies, which a browser attaches to a cross-site request too. A non-GET
// /api request that carries one of those cookies and no Bearer token must
// come from our own pages:
//   • Origin present        → must be allow-listed or this host
//   • else Sec-Fetch-Site    → must be same-origin (or none: typed URL)
//   • neither (old browser / non-browser client) → body must be JSON or
//     multipart, which an HTML form on another site cannot send.
// Bearer-token callers (the native apps) are exempt: a browser never adds an
// Authorization header by itself. The admin cookie is also SameSite=strict.
const AUTH_COOKIES = ['admin_token', 'zone_admin_token', 'driver_token']
const SAFE_METHODS = new Set(['GET', 'HEAD', 'OPTIONS'])

function csrfRefusal(req: NextRequest): string | null {
  if (SAFE_METHODS.has(req.method)) return null
  if (req.headers.get('authorization')?.startsWith('Bearer ')) return null
  if (!AUTH_COOKIES.some(c => req.cookies.get(c)?.value)) return null
  const origin = req.headers.get('origin')
  if (origin) {
    if (ALLOWED_ORIGINS.has(origin)) return null
    const host = req.headers.get('x-forwarded-host') || req.headers.get('host')
    try { if (host && new URL(origin).host === host) return null } catch { /* bad Origin */ }
    return 'Cross-site request refused'
  }
  const site = req.headers.get('sec-fetch-site')
  if (site) return site === 'same-origin' || site === 'none' ? null : 'Cross-site request refused'
  const ct = (req.headers.get('content-type') || '').toLowerCase()
  if (!ct || ct.startsWith('application/json') || ct.startsWith('multipart/form-data')) return null
  return 'Unsupported content type'
}

// The zone admin (franchise) panel has its own sign-in and cookie.
function isZonePanelPath(pathname: string): boolean {
  return (pathname === '/zone-panel' || pathname.startsWith('/zone-panel/')) && pathname !== '/zone-panel/login'
}

function isDashboardPath(pathname: string): boolean {
  return DASHBOARD_PATHS.some(p => pathname === p || pathname.startsWith(`${p}/`))
}

export function middleware(req: NextRequest) {
  const { pathname } = req.nextUrl
  const origin = req.headers.get('origin')

  // ── CORS for API ──
  if (pathname.startsWith('/api/')) {
    const headers = corsHeaders(origin)
    if (req.method === 'OPTIONS') {
      return new NextResponse(null, { status: 204, headers })
    }
    const refused = csrfRefusal(req)
    if (refused) return NextResponse.json({ error: refused, code: 'CSRF' }, { status: 403, headers })
    const res = NextResponse.next()
    for (const [k, v] of Object.entries(headers)) res.headers.set(k, v)
    return res
  }

  // ── Admin auth for dashboard pages ──
  if (isDashboardPath(pathname)) {
    const token = req.cookies.get('admin_token')?.value
    if (!token) {
      const url = req.nextUrl.clone()
      url.pathname = '/login'
      return NextResponse.redirect(url)
    }
  }

  if (isZonePanelPath(pathname) && !req.cookies.get('zone_admin_token')?.value) {
    const url = req.nextUrl.clone()
    url.pathname = '/zone-panel/login'
    return NextResponse.redirect(url)
  }

  // ── Bounce away from /login if already logged in ──
  if (pathname === '/login') {
    const token = req.cookies.get('admin_token')?.value
    if (token) {
      const url = req.nextUrl.clone()
      url.pathname = '/dashboard'
      return NextResponse.redirect(url)
    }
  }

  // ── Public /track/* page (no auth needed) ──
  if (pathname.startsWith('/track/')) {
    return NextResponse.next()
  }

  // ── Bare / → /dashboard (middleware handles auth above) ──
  if (pathname === '/') {
    const url = req.nextUrl.clone()
    url.pathname = '/dashboard'
    return NextResponse.redirect(url)
  }

  return NextResponse.next()
}

export const config = {
  matcher: [
    // Match all paths except: _next, static files, favicon, uploads
    '/((?!_next|favicon|uploads).*)',
  ],
}
