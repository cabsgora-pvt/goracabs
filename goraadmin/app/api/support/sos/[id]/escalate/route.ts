export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import SOSAlert from '@/models/SOSAlert'
import { guardAdmin } from '@/lib/admin-guard'
import { requireAdmin } from '@/lib/auth'
import { auditAdmin } from '@/lib/admin-audit'
import { escalateSos } from '@/lib/sos-escalate'

// POST — send an SOS alert's SMS escalation again (ops phones + the person's
// emergency contacts). The first one is sent when the alert is raised.
export async function POST(req: NextRequest, { params }: { params: { id: string } }) {
  const denied = await guardAdmin(req); if (denied) return denied
  if (!mongoose.isValidObjectId(params.id)) return NextResponse.json({ error: 'Not found' }, { status: 404 })
  await connectDB()
  const alert: any = await SOSAlert.findById(params.id).lean()
  if (!alert) return NextResponse.json({ error: 'Not found' }, { status: 404 })
  const out = await escalateSos(alert)
  await auditAdmin(req, requireAdmin(req), 'sos.escalate', { target: `sos:${params.id}`, summary: `SOS re-sent to ${out.recipients.length} number(s)` })
  return NextResponse.json({ success: true, ...out })
}
