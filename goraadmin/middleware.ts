import { NextRequest, NextResponse } from 'next/server'

// List of dashboard paths that require admin auth
const DASHBOARD_PATHS = [
  '/dashboard', '/users', '/drivers', '/vehicles', '/services',
  '/zones', '/rides', '/finance', '/fleet', '/promos',
  '/support', '/notifications', '/banners', '/settings',
]

function isDashboardPath(pathname: string): boolean {
  return DASHBOARD_PATHS.some(p => pathname === p || pathname.startsWith(`${p}/`))
}

export function middleware(req: NextRequest) {
  const { pathname } = req.nextUrl
  const origin = req.headers.get('origin') || '*'

  // ── CORS for API ──
  if (pathname.startsWith('/api/')) {
    if (req.method === 'OPTIONS') {
      return new NextResponse(null, {
        status: 204,
        headers: {
          'Access-Control-Allow-Origin': origin,
          'Access-Control-Allow-Methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, Authorization',
          'Access-Control-Allow-Credentials': 'true',
        },
      })
    }
    const res = NextResponse.next()
    res.headers.set('Access-Control-Allow-Origin', origin)
    res.headers.set('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS')
    res.headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization')
    res.headers.set('Access-Control-Allow-Credentials', 'true')
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
