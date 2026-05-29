import { NextResponse } from 'next/server'

// Middleware handles CORS headers globally.
// These helpers just return proper JSON responses.

export function withCors(data: object, status = 200) {
  return NextResponse.json(data, { status })
}

export function corsOptions() {
  return new NextResponse(null, { status: 204 })
}
