import jwt from 'jsonwebtoken'
import { NextRequest, NextResponse } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import mongoose from 'mongoose'
import ZoneAdmin from '@/models/ZoneAdmin'
import ZoneStaff from '@/models/ZoneStaff'
import ZoneAdminActivity from '@/models/ZoneAdminActivity'
import Zone from '@/models/Zone'
import ZonePlan from '@/models/ZonePlan'
import { nextSeq } from '@/models/Counter'
import { FEATURE_KEYS, GRACE_DAYS, type ZoneFeature } from '@/lib/zone-features'
import { FRANCHISE_OFF_MESSAGE, isFranchiseMode } from '@/lib/franchise'

// ─────────────────────────────────────────────────────────────────────────────
// Zone admin (franchise) auth.
//
// Their token is typed 'zone_admin', so isAdminPayload() — which accepts only
// untyped tokens — rejects it: no super admin API is reachable with it. It is
// carried in its own cookie, and every zone panel API re-reads the account, so
// blocking it or letting the subscription lapse takes effect on the next
// request, not when the 7-day token expires. A staff member signs in with the
// same token type plus their staff id, and is held to the owner's access too.
// ─────────────────────────────────────────────────────────────────────────────

const JWT_SECRET = process.env.JWT_SECRET!
export const ZONE_ADMIN_COOKIE = 'zone_admin_token'

export function signZoneAdminToken(id: string, extra: { staffId?: string; impersonatedBy?: string } = {}) {
  return jwt.sign({ id, type: 'zone_admin', ...extra }, JWT_SECRET, { expiresIn: extra.impersonatedBy ? '2h' : '7d' })
}

export type AccessState = 'active' | 'grace' | 'blocked' | 'expired' | 'no_subscription'

/**
 * 'grace' is the GRACE_DAYS after expiry: the panel still opens so the zone
 * admin can see their data and renewal details, but nothing can be changed.
 */
export function accessState(a: { status?: string; subscriptionEndAt?: Date | string | null }, now = new Date()): AccessState {
  if (a.status === 'blocked') return 'blocked'
  if (!a.subscriptionEndAt) return 'no_subscription'
  const end = new Date(a.subscriptionEndAt).getTime()
  if (end > now.getTime()) return 'active'
  return end + GRACE_DAYS * 86_400_000 > now.getTime() ? 'grace' : 'expired'
}

export const ACCESS_MESSAGE: Record<Exclude<AccessState, 'active'>, string> = {
  grace: `Your subscription has ended. The panel is read-only for ${GRACE_DAYS} days — renew with Gora to make changes.`,
  blocked: 'Your zone admin account is blocked. Please contact Gora.',
  expired: 'Your subscription has expired. Please renew with Gora to continue.',
  no_subscription: 'No active subscription. Please contact Gora to activate your zone.',
}

export type ZoneActor = { type: 'zone_admin' | 'staff' | 'super_admin'; id: string; name: string }

export type ZoneGuardOk = {
  admin: any
  zoneIds: string[]
  /** Features this caller may use: the admin's, narrowed to a staff member's. */
  features: string[]
  actor: ZoneActor
  isOwner: boolean
  readOnly: boolean
  impersonatedBy?: string
}

function deny(status: number, error: string, extra: Record<string, unknown> = {}) {
  return { denied: NextResponse.json({ error, ...extra }, { status }) }
}

/**
 * First line of every zone panel API.
 *   write   — refuse during the read-only grace period
 *   feature — refuse unless the caller has that feature
 *   ownerOnly — refuse staff (staff management, passwords of the owner)
 */
export async function guardZoneAdmin(
  req: NextRequest,
  opts: { write?: boolean; feature?: ZoneFeature; ownerOnly?: boolean } = {},
): Promise<ZoneGuardOk | { denied: NextResponse }> {
  const auth = req.headers.get('authorization')
  const token = auth?.startsWith('Bearer ') ? auth.slice(7) : req.cookies.get(ZONE_ADMIN_COOKIE)?.value
  let payload: any = null
  try { payload = token ? jwt.verify(token, JWT_SECRET) : null } catch { payload = null }
  if (!payload?.id || payload.type !== 'zone_admin') return deny(401, 'Unauthorized')
  // Franchise mode off: the whole zone panel is closed, for everyone.
  if (!(await isFranchiseMode())) return deny(403, FRANCHISE_OFF_MESSAGE, { access: 'franchise_off' })

  await connectDB()
  const admin: any = await ZoneAdmin.findById(payload.id).select('-password').lean()
  if (!admin) return deny(401, 'Unauthorized')
  const state = accessState(admin)
  if (state !== 'active' && state !== 'grace') return deny(403, ACCESS_MESSAGE[state], { access: state })

  let features: string[] = (admin.features || []).filter((f: string) => FEATURE_KEYS.includes(f))
  let actor: ZoneActor = { type: 'zone_admin', id: String(admin._id), name: admin.name }
  if (payload.impersonatedBy) actor = { type: 'super_admin', id: String(admin._id), name: String(payload.impersonatedBy) }
  if (payload.staffId) {
    const staff: any = await ZoneStaff.findById(payload.staffId).select('-password').lean()
    if (!staff || String(staff.zoneAdminId) !== String(admin._id) || staff.status !== 'active') return deny(401, 'Unauthorized')
    // A staff member never has more than the owner.
    features = features.filter(f => (staff.permissions || []).includes(f))
    actor = { type: 'staff', id: String(staff._id), name: staff.name }
  }
  const isOwner = !payload.staffId
  const readOnly = state === 'grace'

  if (opts.ownerOnly && !isOwner) return deny(403, 'Only the zone admin can do this')
  if (opts.feature && !features.includes(opts.feature)) return deny(403, 'Your plan does not include this feature', { feature: opts.feature })
  if (opts.write && readOnly) return deny(403, ACCESS_MESSAGE.grace, { access: 'grace' })

  return { admin, zoneIds: (admin.zoneIds || []).map(String), features, actor, isOwner, readOnly, impersonatedBy: payload.impersonatedBy }
}

/** Best-effort audit entry; never fails the request it records. */
export async function logZoneActivity(zoneAdminId: any, actor: ZoneActor, action: string, details?: unknown) {
  try {
    await ZoneAdminActivity.create({ zoneAdminId, actorType: actor.type, actorName: actor.name, action, details })
  } catch { /* ignore */ }
}

/** Zone ids already held by another zone admin — a zone has one franchise. */
export async function zonesTakenByOthers(zoneIds: string[], exceptId?: string) {
  const others: any[] = await ZoneAdmin.find({
    zoneIds: { $in: zoneIds.filter(id => mongoose.isValidObjectId(id)) },
    ...(exceptId ? { _id: { $ne: exceptId } } : {}),
  }).select('name zoneIds').lean()
  const taken = new Set<string>()
  for (const o of others) for (const z of o.zoneIds || []) if (zoneIds.includes(String(z))) taken.add(String(z))
  return { taken: Array.from(taken), holders: others.map(o => o.name) }
}

export function publicZoneAdmin(a: any, zoneNames: Map<string, string>) {
  return {
    _id: a._id,
    name: a.name, email: a.email, phone: a.phone,
    businessName: a.businessName, address: a.address, gstNumber: a.gstNumber,
    zoneIds: (a.zoneIds || []).map(String),
    zones: (a.zoneIds || []).map((z: any) => ({ _id: String(z), name: zoneNames.get(String(z)) || 'Unknown zone' })),
    status: a.status,
    access: accessState(a),
    features: a.features || [],
    revenueSharePercent: a.revenueSharePercent || 0,
    priceChangeLimitPct: a.priceChangeLimitPct ?? 30,
    subscriptionEndAt: a.subscriptionEndAt || null,
    payments: (a.payments || []).slice().reverse(),
    totalPaid: (a.payments || []).reduce((s: number, p: any) => s + (p.amount || 0), 0),
    payouts: (a.payouts || []).slice().reverse(),
    passwordResetRequestedAt: a.passwordResetRequestedAt || null,
    lastLoginAt: a.lastLoginAt || null,
    createdAt: a.createdAt,
  }
}

/**
 * Gives a zone admin a period of the chosen plan. Months and price come from
 * the plan, never the request. A renewal before expiry adds on to the current
 * end date, so renewing early never loses days; after expiry it starts today.
 * The plan's features are copied on. Returns an error message, or null after
 * updating [admin] (not saved).
 */
export async function applyPlan(admin: any, planId: unknown, extra: { paymentRef?: string; notes?: string; recordedBy?: string }) {
  if (!mongoose.isValidObjectId(String(planId || ''))) return 'Choose a subscription plan'
  const plan: any = await ZonePlan.findById(String(planId)).lean()
  if (!plan || !plan.isActive) return 'This plan is not available'
  const now = new Date()
  const start = admin.subscriptionEndAt && new Date(admin.subscriptionEndAt) > now ? new Date(admin.subscriptionEndAt) : now
  const end = addMonths(start, plan.months)
  admin.subscriptionEndAt = end
  admin.features = (plan.features || []).filter((f: string) => FEATURE_KEYS.includes(f))
  admin.payments = admin.payments || []
  const seq = await nextSeq('zone-invoice')
  admin.payments.push({
    planId: plan._id, planName: plan.name, amount: plan.price, months: plan.months,
    invoiceNo: `GZA-${now.getFullYear()}-${String(seq).padStart(4, '0')}`,
    paymentRef: extra.paymentRef, notes: extra.notes,
    periodStart: start, periodEnd: end, recordedBy: extra.recordedBy,
  })
  return null
}

/**
 * [months] after [d], on the same day of the month or the month's last day
 * when it is shorter: 31 Jan + 1 month is 28/29 Feb, not 2/3 Mar.
 */
export function addMonths(d: Date, months: number) {
  const y = d.getUTCFullYear(), m = d.getUTCMonth() + months
  const lastDay = new Date(Date.UTC(y, m + 1, 0)).getUTCDate()
  return new Date(Date.UTC(y, m, Math.min(d.getUTCDate(), lastDay),
    d.getUTCHours(), d.getUTCMinutes(), d.getUTCSeconds(), d.getUTCMilliseconds()))
}

export async function zoneNameMap() {
  const zones: any[] = await Zone.find().select('name').lean()
  return new Map(zones.map(z => [String(z._id), z.name as string]))
}

/** Start and end of a YYYY-MM month in IST, as UTC instants. */
export function monthRange(month: string) {
  const m = /^(\d{4})-(\d{2})$/.exec(month)
  const now = new Date(Date.now() + 5.5 * 3600e3)
  const y = m ? Number(m[1]) : now.getUTCFullYear()
  const mo = m ? Number(m[2]) - 1 : now.getUTCMonth()
  const from = new Date(Date.UTC(y, mo, 1) - 5.5 * 3600e3)
  const to = new Date(Date.UTC(y, mo + 1, 1) - 5.5 * 3600e3)
  return { from, to, month: `${y}-${String(mo + 1).padStart(2, '0')}` }
}

/**
 * A zone admin's earnings for one month (IST). Bookkeeping only — the super
 * admin pays it and records the payout.
 *
 *   ride share         — their part of the commission on each ride, as fixed
 *                        on the ride when it completed (ride.franchiseShare)
 *   subscription share — their part of each driver subscription bought in
 *                        their zones (subscribed drivers pay no ride commission)
 *
 * Rides completed before shares were snapshotted carry no franchiseShare; for
 * those the old rule still applies (commission in their zones × current %).
 */
export async function computeSettlement(admin: any, month: string) {
  const Ride = (await import('@/models/Ride')).default
  const DriverSubscription = (await import('@/models/DriverSubscription')).default
  const { from, to, month: m } = monthRange(month)
  const adminId = new mongoose.Types.ObjectId(String(admin._id))
  const zoneObjIds = (admin.zoneIds || []).map((z: any) => new mongoose.Types.ObjectId(String(z)))
  const pct = Number(admin.revenueSharePercent || 0)
  const sum = (f: string) => ({ $sum: { $ifNull: [f, 0] } })

  const [snap, legacy, subs] = await Promise.all([
    Ride.aggregate([
      { $match: { 'franchiseShare.zoneAdminId': adminId, status: 'completed', completedAt: { $gte: from, $lt: to } } },
      { $group: { _id: null, rides: { $sum: 1 }, fare: sum('$totalFare'), commission: sum('$commissionAmount'), share: sum('$franchiseShare.amount') } },
    ]),
    Ride.aggregate([
      { $match: { zoneId: { $in: zoneObjIds }, status: 'completed', completedAt: { $gte: from, $lt: to }, franchiseShare: { $exists: false } } },
      { $group: { _id: null, rides: { $sum: 1 }, fare: sum('$totalFare'), commission: sum('$commissionAmount') } },
    ]),
    DriverSubscription.aggregate([
      { $match: { 'franchiseShare.zoneAdminId': adminId, createdAt: { $gte: from, $lt: to } } },
      { $group: { _id: null, count: { $sum: 1 }, amount: sum('$price'), share: sum('$franchiseShare.amount') } },
    ]),
  ])
  const s = snap[0] || {}, l = legacy[0] || {}, sb = subs[0] || {}
  const r2 = (n: number) => Math.round((n || 0) * 100) / 100
  const commission = (s.commission || 0) + (l.commission || 0)
  const rideShare = r2((s.share || 0) + (l.commission || 0) * pct / 100)
  const subscriptionShare = r2(sb.share || 0)
  const share = r2(rideShare + subscriptionShare)
  const paid = (admin.payouts || []).filter((p: any) => p.month === m).reduce((t: number, p: any) => t + (p.amount || 0), 0)
  return {
    month: m,
    rides: (s.rides || 0) + (l.rides || 0),
    fare: (s.fare || 0) + (l.fare || 0),
    commission, rideShare,
    subscriptions: sb.count || 0, subscriptionAmount: sb.amount || 0, subscriptionShare,
    sharePercent: pct, share, paid,
    due: Math.max(0, r2(share - paid)),
  }
}

/** Everything an invoice page shows for one subscription payment. */
export async function invoiceFor(admin: any, paymentId: string) {
  const Settings = (await import('@/models/Settings')).default
  const p = (admin.payments || []).find((x: any) => String(x._id) === String(paymentId))
  if (!p) return null
  const s: any = await Settings.findOne({ key: 'global' }).select('general').lean()
  const g = s?.general || {}
  const gstPct = Math.max(0, Number(g.invoiceGstPercent) || 0)
  // The plan price is what the zone admin paid, tax included.
  const total = Number(p.amount) || 0
  const taxable = gstPct ? Math.round((total / (1 + gstPct / 100)) * 100) / 100 : total
  return {
    company: {
      name: g.companyLegalName || g.appName || 'Gora Cabs', gstin: g.companyGstin || '', address: g.companyAddress || '',
      email: g.supportEmail || '', phone: g.supportPhone || '',
    },
    billTo: { name: admin.businessName || admin.name, contact: admin.name, email: admin.email, phone: admin.phone, address: admin.address, gstin: admin.gstNumber },
    invoiceNo: p.invoiceNo || `GZA-${String(p._id).slice(-6).toUpperCase()}`,
    date: p.createdAt, planName: p.planName, months: p.months, periodStart: p.periodStart, periodEnd: p.periodEnd,
    paymentRef: p.paymentRef || '',
    gstPercent: gstPct, taxable, tax: Math.round((total - taxable) * 100) / 100, total,
  }
}
