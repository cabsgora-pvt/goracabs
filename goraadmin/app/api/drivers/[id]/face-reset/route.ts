export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { guardAdmin } from '@/lib/admin-guard'

// POST /api/drivers/{id}/face-reset  body: { allow?: boolean (default true) }
// Admin only. Lets a driver whose registration is already submitted/approved
// capture a new reference face ONCE (auth/driver/face-signature clears the
// flag when it is used). Without this the reference face is fixed after
// submission, so an account cannot be handed to someone else by re-enrolling.
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  const denied = guardAdmin(req); if (denied) return denied
  try {
    const b = await req.json().catch(() => ({}))
    const allow = b?.allow !== false
    await connectDB()
    const d: any = await Driver.findByIdAndUpdate(params.id, { $set: { faceResetAllowed: allow } }, { new: true })
      .select('faceResetAllowed').lean()
    if (!d) return NextResponse.json({ error: 'Driver not found' }, { status: 404 })
    return NextResponse.json({ success: true, faceResetAllowed: !!d.faceResetAllowed })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}
