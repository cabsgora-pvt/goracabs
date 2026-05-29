import { NextRequest, NextResponse } from 'next/server'

export function middleware(req: NextRequest) {
  const origin = req.headers.get('origin') || '*'

  // Handle preflight
  if (req.method === 'OPTIONS') {
    return new NextResponse(null, {
      status: 204,
      headers: {
        'Access-Control-Allow-Origin': origin,
        'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        'Access-Control-Allow-Credentials': 'true',
      },
    })
  }

  // Add CORS to actual response
  const res = NextResponse.next()
  res.headers.set('Access-Control-Allow-Origin', origin)
  res.headers.set('Access-Control-Allow-Methods', 'GET,POST,PUT,DELETE,OPTIONS')
  res.headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization')
  res.headers.set('Access-Control-Allow-Credentials', 'true')
  return res
}

export const config = {
  matcher: '/api/:path*',
}
