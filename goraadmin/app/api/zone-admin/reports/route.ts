export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import mongoose from 'mongoose'
import Ride from '@/models/Ride'
import { guardZoneAdmin } from '@/lib/zone-admin'

const IST = 5.5 * 3600e3
const CSV_MAX_ROWS = 20_000

/** YYYY-MM-DD (IST) → UTC instant of that IST midnight. */
function istDay(s: string | null, fallback: Date) {
  const m = s && /^(\d{4})-(\d{2})-(\d{2})$/.exec(s)
  return m ? new Date(Date.UTC(+m[1], +m[2] - 1, +m[3]) - IST) : fallback
}

function csvCell(v: unknown) {
  const s = v == null ? '' : String(v)
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
}

// GET ?from=YYYY-MM-DD&to=YYYY-MM-DD[&format=csv]
// Day-by-day summary of their zones, or every ride as a CSV for Excel.
export async function GET(req: NextRequest) {
  const g = await guardZoneAdmin(req, { feature: 'reports' })
  if ('denied' in g) return g.denied
  try {
    const sp = req.nextUrl.searchParams
    const today = new Date(Math.floor((Date.now() + IST) / 864e5) * 864e5 - IST)
    const from = istDay(sp.get('from'), new Date(today.getTime() - 29 * 864e5))
    const to = new Date(istDay(sp.get('to'), today).getTime() + 864e5) // inclusive end day
    if (to.getTime() - from.getTime() > 370 * 864e5) return NextResponse.json({ error: 'Choose at most one year' }, { status: 400 })
    const match = {
      zoneId: { $in: g.zoneIds.map(id => new mongoose.Types.ObjectId(id)) },
      createdAt: { $gte: from, $lt: to },
    }

    if (sp.get('format') === 'csv') {
      // Capped: a year of a busy zone must not be loaded into memory at once.
      const rides: any[] = await Ride.find(match).sort({ createdAt: 1 }).limit(CSV_MAX_ROWS)
        .select('createdAt completedAt status service vehicleType riderName driverName pickupAddress dropAddress distance paymentMode totalFare commissionAmount driverEarning').lean()
      const head = ['Date (IST)', 'Status', 'Service', 'Vehicle', 'Rider', 'Driver', 'Pickup', 'Drop', 'Km', 'Payment', 'Fare', 'Commission', 'Driver earning']
      const lines = [head.join(',')]
      for (const r of rides) {
        lines.push([
          new Date(new Date(r.createdAt).getTime() + IST).toISOString().replace('T', ' ').slice(0, 16),
          r.status, r.service || 'taxi', r.vehicleType, r.riderName, r.driverName, r.pickupAddress, r.dropAddress,
          r.distance ?? '', r.paymentMode, r.totalFare ?? '', r.commissionAmount ?? '', r.driverEarning ?? '',
        ].map(csvCell).join(','))
      }
      return new NextResponse('﻿' + lines.join('\n'), {
        headers: {
          'Content-Type': 'text/csv; charset=utf-8',
          'X-Rows-Capped': rides.length >= CSV_MAX_ROWS ? String(CSV_MAX_ROWS) : '0',
          'Content-Disposition': `attachment; filename="gora-zone-rides-${sp.get('from') || 'last30'}-to-${sp.get('to') || 'today'}.csv"`,
        },
      })
    }

    const days = await Ride.aggregate([
      { $match: match },
      { $group: {
        _id: { $dateToString: { format: '%Y-%m-%d', date: '$createdAt', timezone: '+05:30' } },
        rides: { $sum: 1 },
        completed: { $sum: { $cond: [{ $eq: ['$status', 'completed'] }, 1, 0] } },
        cancelled: { $sum: { $cond: [{ $eq: ['$status', 'cancelled'] }, 1, 0] } },
        revenue: { $sum: { $cond: [{ $eq: ['$status', 'completed'] }, { $ifNull: ['$totalFare', 0] }, 0] } },
        commission: { $sum: { $cond: [{ $eq: ['$status', 'completed'] }, { $ifNull: ['$commissionAmount', 0] }, 0] } },
      } },
      { $sort: { _id: -1 } },
    ])
    const totals = days.reduce((t: any, d: any) => ({
      rides: t.rides + d.rides, completed: t.completed + d.completed, cancelled: t.cancelled + d.cancelled,
      revenue: t.revenue + d.revenue, commission: t.commission + d.commission,
    }), { rides: 0, completed: 0, cancelled: 0, revenue: 0, commission: 0 })
    return NextResponse.json({ days, totals })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Server error' }, { status: 500 })
  }
}
