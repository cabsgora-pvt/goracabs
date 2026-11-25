import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import PromoCode from '@/models/PromoCode'
import { guardAdmin } from '@/lib/admin-guard'
import { requireAdminPassword } from '@/lib/admin-password'
import { auditAdminBody } from '@/lib/admin-audit'
import { requireAdmin } from '@/lib/auth'

export async function GET(req: NextRequest) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    await connectDB()
    const promos = await PromoCode.find().sort({ createdAt: -1 }).lean()
    return NextResponse.json({ promos })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}

export async function POST(req: NextRequest) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    const noPwd = await requireAdminPassword(req); if (noPwd) return noPwd
    await auditAdminBody(req, requireAdmin(req), 'promo.create', undefined)
    await connectDB()
    const body = await req.json()
    const promo = await PromoCode.create(body)
    return NextResponse.json(promo, { status: 201 })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 400 })
  }
}
