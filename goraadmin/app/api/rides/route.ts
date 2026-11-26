export const dynamic = 'force-dynamic'
import { NextRequest, NextResponse } from 'next/server'
import mongoose from 'mongoose'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import { guardAdmin } from '@/lib/admin-guard'
import { requireAdmin } from '@/lib/auth'
import { auditAdmin } from '@/lib/admin-audit'
import { parsePaging, escapeRegex } from '@/lib/list-params'

// Admin ride list — carries rider phones and ride OTPs, so admin only.
//
// GET /api/rides?page&limit&status&service&dateFrom&dateTo&search&tripType&anomaly=1
//   dateFrom / dateTo are IST calendar days (YYYY-MM-DD), both inclusive, on
//   createdAt. search matches names, phones, cities, vehicle / item type, or
//   a pasted ride id.
//   ← { rides, total, page, limit, stats? }
//   &stats=1 adds counts for the same filters computed in Mongo (status is NOT
//   applied to them, so the cards show the split across statuses):
//   { total, byStatus, revenue, anomalies, byTripType, byPhase }.
// GET ...&format=csv → the same filters as a CSV download (newest first, at
//   most CSV_MAX rows; X-Total-Count / X-Export-Truncated headers). Audited.

const CSV_MAX = 20_000
const DAY_RE = /^\d{4}-\d{2}-\d{2}$/
const PHASE_FIELD: Record<string, string> = {
  rental: 'rentalPhase', hire_driver: 'hirePhase', delivery: 'deliveryPhase', outstation: 'outstationPhase',
}

/** Start / end of an IST calendar day ('YYYY-MM-DD'), or null if malformed. */
function istDayStart(d: string): Date | null {
  if (!DAY_RE.test(d)) return null
  const t = new Date(`${d}T00:00:00.000+05:30`)
  return isNaN(t.getTime()) ? null : t
}
function istDayEnd(d: string): Date | null {
  if (!DAY_RE.test(d)) return null
  const t = new Date(`${d}T23:59:59.999+05:30`)
  return isNaN(t.getTime()) ? null : t
}

function buildQuery(sp: URLSearchParams): { query: any; error?: string } {
  const status = sp.get('status') || ''
  const service = sp.get('service') || ''
  const dateFrom = (sp.get('dateFrom') || '').trim()
  const dateTo = (sp.get('dateTo') || '').trim()
  const tripType = sp.get('tripType') || ''
  const search = escapeRegex((sp.get('search') || '').trim())

  const query: any = {}
  if (status && status !== 'all') query.status = status
  if (service && service !== 'all') query.service = service
  if (tripType && tripType !== 'all') query.tripType = tripType
  if (sp.get('anomaly') === '1') query.kmAnomaly = true
  if (dateFrom || dateTo) {
    query.createdAt = {}
    if (dateFrom) {
      const from = istDayStart(dateFrom)
      if (!from) return { query, error: 'dateFrom must be YYYY-MM-DD' }
      query.createdAt.$gte = from
    }
    if (dateTo) {
      const to = istDayEnd(dateTo)
      if (!to) return { query, error: 'dateTo must be YYYY-MM-DD' }
      query.createdAt.$lte = to
    }
  }
  if (search) {
    const rx = { $regex: search, $options: 'i' }
    query.$or = [
      { riderName: rx }, { driverName: rx }, { riderPhone: rx }, { driverPhone: rx },
      { senderName: rx }, { receiverName: rx }, { cityFrom: rx }, { cityTo: rx },
      { vehicleType: rx }, { itemType: rx },
      // A pasted ride id (links from the Needs Review page) finds that ride.
      ...(/^[a-f0-9]{24}$/i.test(search) ? [{ _id: new mongoose.Types.ObjectId(search) }] : []),
    ]
  }
  return { query }
}

// ── CSV ──
const CSV_COLS: [string, (r: any) => any][] = [
  ['ride_id', r => String(r._id)],
  ['created_ist', r => ist(r.createdAt)],
  ['service', r => r.service],
  ['status', r => r.status],
  ['vehicle_type', r => r.vehicleType],
  ['rider_name', r => r.riderName],
  ['rider_phone', r => r.riderPhone],
  ['driver_name', r => r.driverName],
  ['driver_phone', r => r.driverPhone],
  ['pickup', r => r.pickupAddress],
  ['drop', r => r.dropAddress],
  ['stops', r => Array.isArray(r.stops) ? r.stops.length : 0],
  ['distance_km', r => r.distance],
  ['fare', r => r.fare],
  ['waiting_charge', r => r.waitingChargeTotal],
  ['tip', r => r.tip],
  ['total_fare', r => r.totalFare],
  ['final_fare', r => r.finalFare || r.hireFinalFare || r.deliveryFinalFare],
  ['coupon_code', r => r.couponCode],
  ['coupon_discount', r => r.couponDiscount],
  ['commission', r => r.commissionAmount],
  ['driver_earning', r => r.driverEarning],
  ['payment_mode', r => r.paymentMode],
  ['payment_status', r => r.paymentStatus],
  ['amount_due', r => r.amountDue],
  ['prepaid_amount', r => r.prepaidAmount],
  ['refunded_amount', r => (Number(r.refundedAmount) || 0) + (Number(r.adminRefundTotal) || 0)],
  ['cancellation_fee', r => r.cancellationFee],
  ['cancelled_by', r => r.cancelledBy],
  ['cancellation_reason', r => r.cancellationReason],
  ['completed_ist', r => ist(r.completedAt)],
  ['zone_id', r => r.zoneId ? String(r.zoneId) : ''],
  ['needs_review', r => r.needsReview ? 'yes' : ''],
]

function ist(d: any): string {
  if (!d) return ''
  const t = new Date(d)
  if (isNaN(t.getTime())) return ''
  // 'YYYY-MM-DD HH:mm' in IST, sortable and spreadsheet-friendly.
  return new Date(t.getTime() + 5.5 * 3600e3).toISOString().slice(0, 16).replace('T', ' ')
}

/** One CSV cell: RFC 4180 quoting, and text that a spreadsheet would run as a
 *  formula (=, +, -, @, tab, CR first) is prefixed with ' — except plain
 *  numbers / phone numbers like -12.5 or +91 98…. */
function csvCell(v: any): string {
  if (v === null || v === undefined) return ''
  if (typeof v === 'number') return Number.isFinite(v) ? String(v) : ''
  let s = String(v)
  if (/^[=+\-@\t\r]/.test(s) && !/^[+-]?\d[\d\s.]*$/.test(s)) s = `'${s}`
  if (/[",\r\n]/.test(s) || /^\s|\s$/.test(s) || s.startsWith("'")) s = `"${s.replace(/"/g, '""')}"`
  return s
}

async function csvResponse(req: NextRequest, query: any, sp: URLSearchParams) {
  const total = await Ride.countDocuments(query)
  const istToday = new Date(Date.now() + 5.5 * 3600e3).toISOString().slice(0, 10)
  const name = `rides-${[sp.get('service'), sp.get('status')].filter(s => s && s !== 'all').join('-') || 'all'}-${istToday}.csv`
  await auditAdmin(req, requireAdmin(req), 'rides.export_csv', {
    summary: `Exported ${Math.min(total, CSV_MAX)} of ${total} rides as CSV`,
    details: Object.fromEntries(['status', 'service', 'dateFrom', 'dateTo', 'search', 'tripType', 'anomaly'].map(k => [k, sp.get(k) || undefined])),
  })
  const cursor = Ride.find(query).sort({ createdAt: -1 }).limit(CSV_MAX).select('-messages -routePolyline').lean().cursor({ batchSize: 500 })
  const enc = new TextEncoder()
  let started = false
  const stream = new ReadableStream({
    async pull(controller) {
      try {
        if (!started) {
          started = true
          // BOM so Excel reads the ₹ / non-ASCII names as UTF-8.
          controller.enqueue(enc.encode('﻿' + CSV_COLS.map(c => c[0]).join(',') + '\r\n'))
        }
        let chunk = ''
        for (let i = 0; i < 200; i++) {
          const r = await cursor.next()
          if (!r) {
            if (chunk) controller.enqueue(enc.encode(chunk))
            controller.close()
            return
          }
          chunk += CSV_COLS.map(([, f]) => csvCell(f(r))).join(',') + '\r\n'
        }
        controller.enqueue(enc.encode(chunk))
      } catch (e) {
        controller.error(e)
      }
    },
    async cancel() { await cursor.close().catch(() => {}) },
  })
  return new Response(stream, {
    headers: {
      'Content-Type': 'text/csv; charset=utf-8',
      'Content-Disposition': `attachment; filename="${name}"`,
      'Cache-Control': 'no-store',
      'X-Total-Count': String(total),
      'X-Export-Truncated': total > CSV_MAX ? '1' : '0',
    },
  })
}

async function statsFor(query: any, service: string) {
  const { status: _s, ...base } = query
  const phaseField = PHASE_FIELD[service]
  const [f] = await Ride.aggregate([
    { $match: base },
    {
      $facet: {
        byStatus: [{ $group: { _id: '$status', n: { $sum: 1 } } }],
        revenue: [
          { $match: { status: 'completed' } },
          { $group: { _id: null, sum: { $sum: { $ifNull: ['$totalFare', { $ifNull: ['$fare', 0] }] } } } },
        ],
        anomalies: [{ $match: { kmAnomaly: true } }, { $count: 'n' }],
        byTripType: service === 'outstation' ? [{ $group: { _id: '$tripType', n: { $sum: 1 } } }] : [{ $match: { _id: null } }],
        byPhase: phaseField ? [{ $group: { _id: `$${phaseField}`, n: { $sum: 1 } } }] : [{ $match: { _id: null } }],
      },
    },
  ])
  const toMap = (rows: any[]) => Object.fromEntries((rows || []).map(r => [r._id ?? 'none', r.n]))
  const byStatus = toMap(f?.byStatus)
  return {
    total: Object.values(byStatus).reduce((a: number, b: any) => a + (Number(b) || 0), 0),
    byStatus,
    revenue: Math.round(f?.revenue?.[0]?.sum || 0),
    anomalies: f?.anomalies?.[0]?.n || 0,
    byTripType: toMap(f?.byTripType),
    byPhase: toMap(f?.byPhase),
  }
}

export async function GET(req: NextRequest) {
  try {
    const denied = await guardAdmin(req); if (denied) return denied
    await connectDB()
    const { searchParams } = new URL(req.url)
    const { page, limit, skip } = parsePaging(searchParams)
    const { query, error } = buildQuery(searchParams)
    if (error) return NextResponse.json({ error }, { status: 400 })

    if (searchParams.get('format') === 'csv') return csvResponse(req, query, searchParams)

    const [total, rides, stats] = await Promise.all([
      Ride.countDocuments(query),
      Ride.find(query)
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(limit)
        .select('-messages -routePolyline')
        .lean(),
      searchParams.get('stats') === '1' ? statsFor(query, searchParams.get('service') || '') : Promise.resolve(undefined),
    ])

    return NextResponse.json({ rides, total, page, limit, ...(stats ? { stats } : {}) })
  } catch (error: any) {
    return NextResponse.json({ error: error.message }, { status: 500 })
  }
}
