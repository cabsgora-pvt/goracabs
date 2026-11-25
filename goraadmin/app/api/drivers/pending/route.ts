import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { guardAdmin } from '@/lib/admin-guard'
import { parsePaging } from '@/lib/list-params'

export async function GET(req: NextRequest) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    await connectDB()
    const { page, limit, skip } = parsePaging(req.nextUrl.searchParams, 100)
    const q = { status: 'pending' }
    const [drivers, total] = await Promise.all([
      Driver.find(q).select('-faceSignature -bankDetails -bankAccounts -walletRechargeRefs').sort({ createdAt: -1 }).skip(skip).limit(limit).lean(),
      Driver.countDocuments(q),
    ])
    return NextResponse.json({ drivers, total, page, limit })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
