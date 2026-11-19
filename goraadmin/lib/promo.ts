// ─────────────────────────────────────────────────────────────────────────────
// Server-side promo validation.
//
// Coupons used to be applied entirely on the client: the app subtracted its own
// `couponDiscount` and posted the reduced fare, while /api/rides/book dropped
// `couponCode`/`couponDiscount` on the floor. That meant no redemption record,
// no usage limits enforced, no expiry enforced — and a client could claim any
// discount it liked.
// ─────────────────────────────────────────────────────────────────────────────
import PromoCode from '@/models/PromoCode'
import { isFranchiseMode } from '@/lib/franchise'
import { ZONE_PROMOS_LIVE } from '@/lib/zone-features'

export type PromoResult = {
  code: string
  discount: number
  applied: boolean
  reason?: string
}

/**
 * Validates `code` against `amount` and returns the discount the SERVER is
 * willing to grant. Never throws — an invalid code yields a zero discount so a
 * booking is never blocked by a bad coupon.
 */
export async function evaluatePromo(rawCode: string | undefined | null, amount: number, zoneId?: unknown): Promise<PromoResult> {
  const code = String(rawCode || '').trim().toUpperCase()
  if (!code) return { code: '', discount: 0, applied: false }

  try {
    const promo: any = await PromoCode.findOne({ code, isActive: true }).lean()
    if (!promo) return { code, discount: 0, applied: false, reason: 'Invalid code' }
    // A zone admin's code is for rides in their zones only — and one of theirs
    // with no zones left is valid nowhere, never everywhere.
    // Zone admins' codes exist only while franchise mode is on.
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

    let discount = promo.type === 'flat'
      ? Number(promo.value) || 0
      : (amount * (Number(promo.value) || 0)) / 100

    if (promo.maxDiscount != null && promo.maxDiscount > 0) {
      discount = Math.min(discount, promo.maxDiscount)
    }
    discount = Math.max(0, Math.min(Math.round(discount), Math.round(amount)))

    return { code, discount, applied: discount > 0 }
  } catch {
    return { code, discount: 0, applied: false, reason: 'Could not validate code' }
  }
}

/** Records a redemption. Best-effort — never blocks a completed booking. */
export async function consumePromo(code: string): Promise<void> {
  if (!code) return
  try {
    await PromoCode.updateOne({ code: code.toUpperCase() }, { $inc: { usedCount: 1 } })
  } catch {
    /* ignore */
  }
}
