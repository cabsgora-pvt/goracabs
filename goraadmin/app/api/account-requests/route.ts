export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import AccountRequest from '@/models/AccountRequest'
import { guardAdmin } from '@/lib/admin-guard'

// GET ?status=pending|all&kind=delete|zone_change → requests, newest first,
// plus the count of pending ones (for the sidebar badge).
export async function GET(req: NextRequest) {
  const denied = guardAdmin(req); if (denied) return denied
  await connectDB()
  const sp = req.nextUrl.searchParams
  const status = sp.get('status') || 'pending'
  const kind = sp.get('kind') || ''
  const q: any = {}
  if (status !== 'all') q.status = status
  if (kind) q.kind = kind
  const [requests, pending] = await Promise.all([
    AccountRequest.find(q).sort({ createdAt: -1 }).limit(300).lean(),
    AccountRequest.countDocuments({ status: 'pending' }),
  ])
  return NextResponse.json({ requests, pending })
}
