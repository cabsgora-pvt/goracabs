import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import VehicleType from '@/models/VehicleType'
import { cleanTierFields, warmVehicleTiers, tierView } from '@/lib/vehicle-tiers'
import { guardAdmin } from '@/lib/admin-guard'
import { requireAdminPassword } from '@/lib/admin-password'
import { auditAdminBody } from '@/lib/admin-audit'
import { requireAdmin } from '@/lib/auth'

export async function GET() {
  try {
    await connectDB()
    const rows: any[] = await VehicleType.find().sort({ sortOrder: 1, createdAt: 1 }).lean()
    // Each type with its category / tier / tagline / requirements (stored or
    // inferred from the name) — the driver app groups registration by category.
    // storedCategory / storedRank: what the admin actually set ('' / null =
    // auto-detect from the name) — the admin form needs it, since `category`
    // and `rank` here are the effective (possibly inferred) values.
    const types = rows.map(t => ({ ...t, ...tierView(t), storedCategory: String(t.category || ''), storedRank: Number(t.rank) >= 1 ? Number(t.rank) : null }))
    return NextResponse.json({ types })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}

export async function POST(req: NextRequest) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    const noPwd = await requireAdminPassword(req); if (noPwd) return noPwd
    await auditAdminBody(req, requireAdmin(req), 'vehicle_type.create', undefined)
    await connectDB()
    const body = cleanTierFields(await req.json())
    const type = await VehicleType.create(body)
    await warmVehicleTiers(true)
    return NextResponse.json(type, { status: 201 })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 400 })
  }
}
