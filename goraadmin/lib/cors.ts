import { NextResponse } from 'next/server'

export function corsHeaders() {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  }
}

export function withCors(data: object, status = 200) {
  return NextResponse.json(data, { status, headers: corsHeaders() })
}

export function corsOptions() {
  return new NextResponse(null, { status: 204, headers: corsHeaders() })
}
