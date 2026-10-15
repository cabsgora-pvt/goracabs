// ─────────────────────────────────────────────────────────────────────────────
// Extra charges for rentals and driver hire — one formula, used everywhere.
//
// These were computed inline in four places: rental 'end', rental live ping,
// hire 'end' and hire live ping. The rider's ride screen needs the same figure,
// which would have been a fifth copy. Copies of a billing formula drift, and a
// drifted copy means the running total a rider watches disagrees with the bill
// they are finally charged. So every caller uses this.
//
// The arithmetic is deliberately IDENTICAL to what the inline copies did —
// whole units rounded up, times the per-unit rate — so moving to this module
// changes no amount anywhere. tests/ride-extras.test.mjs proves that across a
// sweep of values against the original inline expressions.
// ─────────────────────────────────────────────────────────────────────────────

export type RentalExtras = {
  extraHours: number
  extraKm: number
  extraHoursCharge: number
  extraKmCharge: number
  /** extraHoursCharge + extraKmCharge, unrounded — exactly as the bill adds it. */
  total: number
}

/** Extra hours and extra km beyond a rental package, and what they cost. */
export function rentalExtras(ride: any): RentalExtras {
  const extraHours = Math.max(0, Math.ceil((ride?.actualHours || 0) - (ride?.packageHours || 0)))
  const extraKm = Math.max(0, Math.ceil((ride?.actualKm || 0) - (ride?.packageKm || 0)))
  const extraHoursCharge = extraHours * (ride?.extraHourRate || 0)
  const extraKmCharge = extraKm * (ride?.extraKmRate || 0)
  return { extraHours, extraKm, extraHoursCharge, extraKmCharge, total: extraHoursCharge + extraKmCharge }
}

export type HireExtras = {
  extraHours: number
  extraCharge: number
}

/** Overtime hours beyond a driver-hire booking, and what they cost. */
export function hireExtras(ride: any): HireExtras {
  const extraHours = Math.max(0, Math.ceil((ride?.hireActualHours || 0) - (ride?.hireTotalHours || 0)))
  return { extraHours, extraCharge: extraHours * (ride?.hirePerHour || 0) }
}
