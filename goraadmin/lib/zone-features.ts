// Zone admin panel features. A plan grants a set; the super admin can adjust
// it per zone admin; a zone admin can give their staff a subset. Shared by the
// server and both panels, so it has no server-only imports.

export const ZONE_FEATURES = [
  { key: 'pricing', label: 'Set zone fares' },
  { key: 'drivers', label: 'Approve / block drivers' },
  { key: 'live_map', label: 'Live map' },
  { key: 'support', label: 'Support tickets & SOS' },
  { key: 'promos', label: 'Zone promo codes (coming soon)' },
  { key: 'reports', label: 'Reports & downloads' },
  { key: 'staff', label: 'Staff logins' },
] as const

export type ZoneFeature = typeof ZONE_FEATURES[number]['key']
export const FEATURE_KEYS: string[] = ZONE_FEATURES.map(f => f.key)

/** Only known feature keys, de-duplicated. */
export function cleanFeatures(v: unknown): string[] {
  return Array.isArray(v) ? Array.from(new Set(v.map(String).filter(k => FEATURE_KEYS.includes(k)))) : []
}

/**
 * Zone admins' promo codes are not live yet. The rider app checks coupons
 * against the app-config list on the phone and only rental bookings are
 * checked on the server, so a zone code showed "Invalid coupon" to the rider
 * while a rental was still discounted. They go live with the coupon update
 * (one server check for every service); until then none can be created and
 * none apply.
 */
export const ZONE_PROMOS_LIVE = false

/** Days after expiry during which the panel still opens, read-only. */
export const GRACE_DAYS = 3

/** Limits on a zone admin's own promo codes. */
export const ZONE_PROMO_CAPS = { maxPercent: 50, maxFlat: 500, maxDiscount: 500 }

export function validZonePromo(b: any): string | null {
  const type = b.type === 'flat' ? 'flat' : 'percent'
  const value = Number(b.value)
  if (!Number.isFinite(value) || value <= 0) return 'Enter the discount value'
  if (type === 'percent' && value > ZONE_PROMO_CAPS.maxPercent) return `Percent discount can be at most ${ZONE_PROMO_CAPS.maxPercent}%`
  if (type === 'flat' && value > ZONE_PROMO_CAPS.maxFlat) return `Flat discount can be at most ₹${ZONE_PROMO_CAPS.maxFlat}`
  const maxDiscount = Number(b.maxDiscount || 0)
  if (type === 'percent' && !(maxDiscount > 0 && maxDiscount <= ZONE_PROMO_CAPS.maxDiscount)) {
    return `Set a maximum discount (up to ₹${ZONE_PROMO_CAPS.maxDiscount}) for a percent code`
  }
  return null
}

/** Fare fields a zone admin may set (zone-admin/pricing); the rest are Gora's. */
export const PRICING_FIELDS = [
  'baseFare', 'perKm', 'perMin', 'perHour', 'hireReturnCharge', 'perKg', 'minFare',
  'nightHaltCharge', 'emptyReturnPercent', 'outPerHour', 'rtBaseFare', 'rtPerKm', 'rtPerHour',
  'kmLimitPerDay', 'extraKmRate', 'driverAllowance',
] as const
export const RENTAL_FIELDS = ['hours', 'km', 'basePrice', 'extraHourRate', 'extraKmRate', 'nightCharge'] as const

/**
 * The reference a zone admin's fare limit is measured from, after a super
 * admin save of [incoming] over [stored]: kept when the super admin left this
 * row's fares as they were (a "Save All" that only touched another row), and
 * dropped when the super admin set new fares — those become the reference.
 */
export function keptAdminRef(stored: any, incoming: any, fields: readonly string[]) {
  if (!stored?.adminRef) return undefined
  const changed = fields.some(k => incoming[k] !== undefined && Number(incoming[k]) !== Number(stored[k] ?? 0))
  return changed ? undefined : stored.adminRef
}
