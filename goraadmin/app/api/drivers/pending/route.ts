import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Driver from '@/models/Driver'
import { guardAdmin } from '@/lib/admin-guard'
import { parsePaging, escapeRegex } from '@/lib/list-params'
import { maskBank } from '@/lib/bank-mask'


// GET ?zoneId=&vehicle=&q=&page&limit — the approval queue, OLDEST first (first
// come, first reviewed). Bank details are masked (holder, bank, IFSC, last 4).
export async function GET(req: NextRequest) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    await connectDB()
    const sp = req.nextUrl.searchParams
    const { page, limit, skip } = parsePaging(sp, 50)
    const q: any = { status: 'pending' }
    const zoneId = sp.get('zoneId') || ''
    if (zoneId === 'none') q.$or = [{ zoneId: { $in: [null, ''] } }]
    else if (zoneId) q.zoneId = zoneId
    const vehicle = escapeRegex((sp.get('vehicle') || '').trim())
    if (vehicle) q.$and = [{ $or: [{ selectedVehicleTypeName: { $regex: `^${vehicle}$`, $options: 'i' } }, { vehicleType: { $regex: `^${vehicle}$`, $options: 'i' } }] }]
    const search = escapeRegex((sp.get('q') || '').trim())
    if (search) (q.$and ||= []).push({ $or: [{ name: { $regex: search, $options: 'i' } }, { phone: { $regex: search } }, { vehicleRegistrationNumber: { $regex: search, $options: 'i' } }] })
    const [rows, total] = await Promise.all([
      Driver.find(q).select('-faceSignature -bankAccounts -walletRechargeRefs').sort({ createdAt: 1, _id: 1 }).skip(skip).limit(limit).lean(),
      Driver.countDocuments(q),
    ])
    const drivers = rows.map((d: any) => ({ ...d, bankDetails: maskBank(d.bankDetails) }))
    return NextResponse.json({ drivers, total, page, limit })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
