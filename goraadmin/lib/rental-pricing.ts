// ─────────────────────────────────────────────────────────────────────────────
// Server-authoritative rental pricing.
//
// Rental fares used to be whatever the client posted: /api/rides/book only
// recomputes a fare when a zone.pricing row matches (vehicleType, service), and
// rental pricing lives in zone.rentalPackages — never in zone.pricing — so
// pricingRow was ALWAYS null for rental and `computedFare = b.fare` stood. A
// patched client could book an 8-hour rental for ₹1.
//
// The arithmetic below intentionally reproduces, exactly, the rule the app was
// already applying client-side (nearest package by hours, then linear scaling),
// so this closes the hole WITHOUT moving any customer's price.
// ─────────────────────────────────────────────────────────────────────────────
import { istParts } from './eta'

export type RentalQuote = {
  packageId: string | null
  vehicleTypeName: string
  hours: number
  km: number
  fare: number
  extraHourRate: number
  extraKmRate: number
  nightCharge: number
  commissionPercent: number
}

export const RENTAL_LIMITS = { MIN_HOURS: 1, MAX_HOURS: 24 }

/** Night window in IST — a package's nightCharge applies if the rental overlaps it. */
const NIGHT_START_HOUR = 22
const NIGHT_END_HOUR = 6

function isNightHour(h: number): boolean {
  return h >= NIGHT_START_HOUR || h < NIGHT_END_HOUR
}

/**
 * True when a rental starting at `startAt` and running `hours` touches the
 * night window. Walks hour by hour, so a 20:00 + 4h booking counts as night.
 */
export function spansNight(startAt: Date, hours: number): boolean {
  const start = istParts(startAt).hour
  for (let i = 0; i <= Math.ceil(hours); i++) {
    if (isNightHour((start + i) % 24)) return true
  }
  return false
}

/**
 * Price a rental from the zone's configured packages.
 * Returns null when the zone has no active package for that vehicle type.
 */
export function quoteRental(params: {
  zone: any
  vehicleType: string
  hours: number
  startAt?: Date | null
}): RentalQuote | null {
  const { zone, vehicleType } = params
  const hours = Math.max(
    RENTAL_LIMITS.MIN_HOURS,
    Math.min(RENTAL_LIMITS.MAX_HOURS, Math.round(Number(params.hours) || 0)),
  )

  const packages = (zone?.rentalPackages || []).filter(
    (p: any) => p.isActive !== false && p.vehicleTypeName === vehicleType,
  )
  if (!packages.length) return null

  // Nearest package by hours — same selection the app made.
  let best: any = packages[0]
  let bestDiff = Math.abs((Number(best.hours) || 0) - hours)
  for (const p of packages) {
    const diff = Math.abs((Number(p.hours) || 0) - hours)
    if (diff < bestDiff) { best = p; bestDiff = diff }
  }

  const pkgHours = Number(best.hours) || 0
  const pkgKm = Number(best.km) || 0
  const basePrice = Number(best.basePrice) || 0

  // Linear scaling from the package rate — mirrors _hourlyRate/_scaledPrice.
  const hourlyRate = pkgHours > 0 ? Math.round(basePrice / pkgHours) : basePrice
  const kmPerHour = pkgHours > 0 ? Math.round(pkgKm / pkgHours) : pkgKm

  const startAt = params.startAt ?? new Date()
  const night = spansNight(startAt, hours) ? Number(best.nightCharge) || 0 : 0

  return {
    packageId: best._id ? String(best._id) : null,
    vehicleTypeName: vehicleType,
    hours,
    km: kmPerHour * hours,
    fare: hourlyRate * hours,
    // A rate of 0 means "admin left it blank" — fall back to the derived hourly
    // rate so extra time is never free. (The app used `??`, which only caught
    // null and let a configured 0 through as genuinely free.)
    extraHourRate: Number(best.extraHourRate) > 0 ? Number(best.extraHourRate) : hourlyRate,
    extraKmRate: Number(best.extraKmRate) || 0,
    nightCharge: night,
    commissionPercent: best.commissionPercent != null ? Number(best.commissionPercent) : 20,
  }
}
