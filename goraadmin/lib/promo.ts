// ─────────────────────────────────────────────────────────────────────────────
// Server-side coupon validation and redemption, for EVERY service.
//
// Two coupon sources, checked in this order:
//   1. PromoCode documents (admin Promo Codes page, zone admins' codes) —
//      expiry, zone, usage cap (maxUses), minimum fare, % with cap or flat.
//   2. The admin-managed AppConfig('user').coupons list the rider app shows —
//      { code, discountType 'flat'|'percent', value, maxDiscount (0 = no cap),
//        minFare, service ('all' or one service), isActive, expiry } — the same
//      rules the app's payment_coupon_bar applies on the phone.
//
// The discount is computed HERE from the server's own fare; the client's
// couponDiscount is ignored. Redemption (redeemPromo) is atomic:
//   • per rider: one use of a code per rider (a claim "coupon:<CODE>" on the
//     rider, $ne-guarded), unless a PromoCode carries perRiderLimit > 1;
//   • per code: usedCount is incremented only while usedCount < maxUses, so
//     two riders racing for the last use cannot both get it.
// A ride cancelled before its trip started gives the use back (releasePromo).
//
// Who funds the discount: Gora. Commission is still taken on the full fare;
// on a cash ride the driver collects fare − discount and Gora credits the
// discount back to the driver's wallet at settlement (lib/settlement.ts).
// ─────────────────────────────────────────────────────────────────────────────
import PromoCode from '@/models/PromoCode'
import AppConfig from '@/models/AppConfig'
import Ride from '@/models/Ride'
import User from '@/models/User'
import { isFranchiseMode } from '@/lib/franchise'
import { ZONE_PROMOS_LIVE } from '@/lib/zone-features'

export type PromoResult = {
  code: string
  discount: number
  applied: boolean
  reason?: string
  source?: 'promo' | 'app'
  perRiderLimit?: number
}

const riderToken = (code: string) => `coupon:${code}`

function clampDiscount(d: number, amount: number): number {
  return Math.max(0, Math.min(Math.round(d), Math.round(amount)))
}

async function usedByRider(riderId: string | undefined, code: string): Promise<number> {
  if (!riderId) return 0
  return Ride.countDocuments({ riderId, couponCode: code, status: { $ne: 'cancelled' } })
}

/**
 * Validates `code` against `amount` (the fare before tip) and returns the
 * discount the SERVER grants. Never throws — an invalid code yields a zero
 * discount, so a booking is never blocked by a bad coupon.
 */
export async function evaluatePromo(
  rawCode: string | undefined | null,
  amount: number,
  zoneId?: unknown,
  opts: { service?: string; riderId?: string } = {},
): Promise<PromoResult> {
  const code = String(rawCode || '').trim().toUpperCase()
  if (!code) return { code: '', discount: 0, applied: false }

  try {
    const promo: any = await PromoCode.findOne({ code, isActive: true }).lean()
    if (promo) {
      // A zone admin's code is for rides in their zones only, and exists only
      // while franchise mode is on.
      if (promo.createdByZoneAdmin && (!ZONE_PROMOS_LIVE || !(await isFranchiseMode()))) {
        return { code, discount: 0, applied: false, reason: 'Invalid code' }
      }
      const zoneLimited = (Array.isArray(promo.zoneIds) && promo.zoneIds.length > 0) || !!promo.createdByZoneAdmin
      if (zoneLimited && !(promo.zoneIds || []).map(String).includes(String(zoneId || ''))) {
        return { code, discount: 0, applied: false, reason: 'Code not valid in this area' }
      }
      if (promo.expiryDate && new Date(promo.expiryDate).getTime() < Date.now()) {
        return { code, discount: 0, applied: false, reason: 'Code expired' }
      }
      if (promo.maxUses != null && promo.maxUses > 0 && (promo.usedCount || 0) >= promo.maxUses) {
        return { code, discount: 0, applied: false, reason: 'Code fully redeemed' }
      }
      if (promo.minOrderAmount != null && amount < promo.minOrderAmount) {
        return { code, discount: 0, applied: false, reason: `Minimum fare ₹${promo.minOrderAmount}` }
      }
      const perRiderLimit = Math.max(1, Math.floor(Number(promo.perRiderLimit) || 1))
      if ((await usedByRider(opts.riderId, code)) >= perRiderLimit) {
        return { code, discount: 0, applied: false, reason: 'You have already used this code' }
      }
      let discount = promo.type === 'flat'
        ? Number(promo.value) || 0
        : (amount * (Number(promo.value) || 0)) / 100
      if (promo.maxDiscount != null && promo.maxDiscount > 0) discount = Math.min(discount, promo.maxDiscount)
      discount = clampDiscount(discount, amount)
      return { code, discount, applied: discount > 0, source: 'promo', perRiderLimit }
    }

    // ── Admin AppConfig coupons (what the rider app lists) ──
    const cfg: any = await AppConfig.findOne({ app: 'user' }).select('coupons').lean()
    const c: any = (cfg?.coupons || []).find((x: any) => String(x?.code || '').trim().toUpperCase() === code)
    if (!c || c.isActive === false) return { code, discount: 0, applied: false, reason: 'Invalid code' }
    if (c.expiry && new Date(c.expiry).getTime() < Date.now()) return { code, discount: 0, applied: false, reason: 'Code expired' }
    const svc = String(c.service || 'all')
    if (svc !== 'all' && opts.service && svc !== opts.service) {
      return { code, discount: 0, applied: false, reason: 'Code not valid for this service' }
    }
    if (Number(c.minFare) > 0 && amount < Number(c.minFare)) {
      return { code, discount: 0, applied: false, reason: `Minimum fare ₹${c.minFare}` }
    }
    if ((await usedByRider(opts.riderId, code)) >= 1) {
      return { code, discount: 0, applied: false, reason: 'You have already used this code' }
    }
    const val = Number(c.value) || 0
    let discount = 0
    if ((c.discountType || 'flat') === 'percent') {
      discount = Math.round((amount * val) / 100)
      const cap = Math.floor(Number(c.maxDiscount) || 0)
      if (cap > 0 && discount > cap) discount = cap
    } else {
      discount = Math.round(val)
    }
    discount = clampDiscount(discount, amount)
    return { code, discount, applied: discount > 0, source: 'app', perRiderLimit: 1 }
  } catch {
    return { code, discount: 0, applied: false, reason: 'Could not validate code' }
  }
}

/**
 * Atomically redeem an evaluated code for this rider. Returns false (and
 * reserves nothing) when the rider already used it or the code just ran out.
 */
export async function redeemPromo(p: PromoResult, riderId: string): Promise<boolean> {
  if (!p.applied || !p.code || !riderId) return false
  const token = riderToken(p.code)
  const oncePerRider = (p.perRiderLimit || 1) <= 1
  if (oncePerRider) {
    const got = await User.updateOne({ _id: riderId, walletRechargeRefs: { $ne: token } }, { $push: { walletRechargeRefs: token } })
    if (!got.modifiedCount) return false
  }
  if (p.source === 'promo') {
    const inc = await PromoCode.updateOne(
      {
        code: p.code, isActive: true,
        $or: [
          { maxUses: { $in: [null, 0] } },
          { maxUses: { $exists: false } },
          { $expr: { $lt: [{ $ifNull: ['$usedCount', 0] }, '$maxUses'] } },
        ],
      },
      { $inc: { usedCount: 1 } },
    )
    if (!inc.modifiedCount) {
      if (oncePerRider) await User.updateOne({ _id: riderId }, { $pull: { walletRechargeRefs: token } })
      return false
    }
  }
  return true
}

/** Give a redemption back (booking refused, or ride cancelled before its trip). */
export async function releasePromo(code: string | undefined | null, source: string | undefined | null, riderId: any): Promise<void> {
  const c = String(code || '').trim().toUpperCase()
  if (!c) return
  try {
    if (riderId) await User.updateOne({ _id: riderId }, { $pull: { walletRechargeRefs: riderToken(c) } })
    if (source === 'promo') await PromoCode.updateOne({ code: c, usedCount: { $gt: 0 } }, { $inc: { usedCount: -1 } })
  } catch (e) {
    console.error('[promo] release failed', e)
  }
}

/** @deprecated use redeemPromo — kept for callers that only count usage. */
export async function consumePromo(code: string): Promise<void> {
  if (!code) return
  try {
    await PromoCode.updateOne({ code: code.toUpperCase() }, { $inc: { usedCount: 1 } })
  } catch {
    /* ignore */
  }
}
