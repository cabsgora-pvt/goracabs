// Vehicle categories and tiers (Cab → Cab / Prime Sedan / Prime SUV), the
// rules a vehicle must meet for a tier, and which drivers may take which ride.
//
// Each VehicleType belongs to a CATEGORY (bike, auto, cab, truck …) and has a
// RANK inside it (1 = basic, higher = premium). Both can be set by the admin;
// when they are not, they are inferred from the name, so the types that already
// exist ("Cab", "Prime Sedan", "Prime SUV") work without editing anything.
//
// Upgrades: a driver of a HIGHER tier in the same category who switched on
// `acceptLowerTiers` may also take rides booked for a lower tier (a Prime SUV
// driver taking a Cab ride). The rider pays the fare of the tier they booked and
// the driver earns from that fare — nothing about the money changes. Off by
// default; never the other way round (a Cab is never sent for a Prime SUV ride).

import VehicleType from '@/models/VehicleType'

export const CATEGORY_LABELS: Record<string, string> = {
  bike: 'Bike', scooter: 'Scooter', auto: 'Auto', cab: 'Cab', truck: 'Truck', other: 'Other',
}

export function inferCategory(name: any): string {
  const n = String(name || '').toLowerCase()
  if (/truck|tempo|loader|cargo|goods|pickup|\bace\b/.test(n)) return 'truck'
  if (/scoot/.test(n)) return 'scooter'
  if (/bike|moto|two.?wheel/.test(n)) return 'bike'
  if (/auto|rick/.test(n)) return 'auto'
  return 'cab'
}

export function inferRank(name: any): number {
  const n = String(name || '').toLowerCase()
  if (/suv|\bxl\b|innova|7.?seat|6.?seat/.test(n)) return 3
  if (/prime|premium|premier|sedan|luxury|comfort/.test(n)) return 2
  return 1
}

export type Requirements = { minModelYear?: number; minDriverRating?: number; allowedModels?: string[]; note?: string }

export function categoryOf(vt: any): string {
  const c = String(vt?.category || '').trim().toLowerCase()
  return c || inferCategory(vt?.name)
}
export function rankOf(vt: any): number {
  const r = Number(vt?.rank)
  return Number.isFinite(r) && r >= 1 ? Math.round(r) : inferRank(vt?.name)
}

export function requirementsOf(vt: any): Requirements {
  const q = vt?.requirements || {}
  const out: Requirements = {}
  const y = Number(q.minModelYear); if (Number.isFinite(y) && y >= 1990) out.minModelYear = Math.round(y)
  const r = Number(q.minDriverRating); if (Number.isFinite(r) && r > 0) out.minDriverRating = Math.min(5, r)
  const models = Array.isArray(q.allowedModels) ? q.allowedModels.map((m: any) => String(m || '').trim()).filter(Boolean) : []
  if (models.length) out.allowedModels = models.slice(0, 50)
  const note = String(q.note || '').trim(); if (note) out.note = note.slice(0, 200)
  return out
}

/** Human summary of a tier's rules: "2019 or newer · rating 4.5+ · Dzire, Aura, Ciaz". */
export function requirementsText(req: Requirements): string {
  const parts: string[] = []
  if (req.minModelYear) parts.push(`${req.minModelYear} or newer`)
  if (req.minDriverRating) parts.push(`rating ${req.minDriverRating}+`)
  if (req.allowedModels?.length) parts.push(req.allowedModels.slice(0, 6).join(', ') + (req.allowedModels.length > 6 ? '…' : ''))
  if (req.note) parts.push(req.note)
  return parts.join(' · ')
}

/** The extra fields every API that lists vehicle types adds. */
export function tierView(vt: any) {
  const category = categoryOf(vt)
  const requirements = requirementsOf(vt)
  return {
    category,
    categoryLabel: CATEGORY_LABELS[category] || category.charAt(0).toUpperCase() + category.slice(1),
    rank: rankOf(vt),
    tagline: String(vt?.tagline || '').trim().slice(0, 80),
    requirements,
    requirementsText: requirementsText(requirements),
  }
}

/** Why this vehicle / driver does not meet a tier's rules (empty = eligible). */
export function eligibilityProblems(vt: any, v: { vehicleModel?: any; vehicleYear?: any; rating?: any; ratingCount?: any }): string[] {
  const req = requirementsOf(vt)
  const out: string[] = []
  if (req.minModelYear) {
    const y = Number(v.vehicleYear)
    if (!Number.isFinite(y) || y < 1990) out.push(`Enter your vehicle's model year (${vt.name} needs ${req.minModelYear} or newer)`)
    else if (y < req.minModelYear) out.push(`${vt.name} needs a ${req.minModelYear} or newer vehicle (yours is ${y})`)
  }
  if (req.allowedModels?.length) {
    const m = String(v.vehicleModel || '').toLowerCase()
    const ok = m && req.allowedModels.some(a => m.includes(a.toLowerCase()))
    if (!ok) out.push(`${vt.name} allows these models: ${req.allowedModels.join(', ')}`)
  }
  // A rating rule applies to drivers who already have ratings (new drivers start without one).
  if (req.minDriverRating) {
    const r = Number(v.rating)
    if (Number.isFinite(r) && r > 0 && r < req.minDriverRating) out.push(`${vt.name} needs a driver rating of ${req.minDriverRating}+ (yours is ${r.toFixed(1)})`)
  }
  return out
}

// ── Cached type list (dispatch is a hot path) ───────────────────────────────
type Tier = { name: string; category: string; rank: number }
let cache: { at: number; tiers: Tier[] } | null = null
const TTL_MS = 60_000

/** Loads (at most once a minute) the active types; call before the sync helpers. */
export async function warmVehicleTiers(force = false): Promise<void> {
  if (!force && cache && Date.now() - cache.at < TTL_MS) return
  try {
    const all: any[] = await VehicleType.find({ isActive: { $ne: false } }).select('name category rank').lean()
    cache = { at: Date.now(), tiers: all.map(v => ({ name: String(v.name), category: categoryOf(v), rank: rankOf(v) })) }
  } catch {
    if (!cache) cache = { at: Date.now(), tiers: [] }
  }
}
export function _setTiersForTest(tiers: Tier[] | null) { cache = tiers ? { at: Date.now(), tiers } : null }

function tierOf(name: any): Tier | undefined {
  return cache?.tiers.find(t => t.name === String(name))
}

/** Higher tiers of the same category ("Cab" → ["Prime Sedan", "Prime SUV"]). */
export function higherTiersOf(name: any): string[] {
  const t = tierOf(name); if (!t) return []
  return cache!.tiers.filter(x => x.category === t.category && x.rank > t.rank).map(x => x.name)
}

/** Lower tiers of the same category ("Prime SUV" → ["Cab", "Prime Sedan"]). */
export function lowerTiersOf(name: any): string[] {
  const t = tierOf(name); if (!t) return []
  return cache!.tiers.filter(x => x.category === t.category && x.rank < t.rank).map(x => x.name)
}

/** Ride vehicle types this driver may take: their own, plus lower tiers when opted in. */
export function rideTypesFor(driver: any): string[] {
  const own = String(driver?.selectedVehicleTypeName || '')
  if (!own) return []
  return driver?.acceptLowerTiers === true ? [own, ...lowerTiersOf(own)] : [own]
}

/** Mongo filter for drivers who may take a ride booked for `vehicleType`. */
export function takersFilter(vehicleType: any): Record<string, any> {
  const higher = higherTiersOf(vehicleType)
  if (!higher.length) return { selectedVehicleTypeName: vehicleType }
  return { $or: [{ selectedVehicleTypeName: vehicleType }, { selectedVehicleTypeName: { $in: higher }, acceptLowerTiers: true }] }
}

/** In-memory twin of takersFilter for one driver. */
export function driverMayTakeType(driver: any, vehicleType: any): boolean {
  return rideTypesFor(driver).includes(String(vehicleType))
}

/** Normalises the tier fields an admin sends (create / update a vehicle type). */
export function cleanTierFields(body: any): any {
  if (!body || typeof body !== 'object') return body
  const out = { ...body }
  if ('category' in out) out.category = String(out.category || '').trim().toLowerCase().replace(/[^a-z_-]/g, '').slice(0, 20)
  if ('rank' in out) {
    const r = Number(out.rank)
    out.rank = Number.isFinite(r) && r >= 1 ? Math.min(9, Math.round(r)) : null
  }
  if ('tagline' in out) out.tagline = String(out.tagline || '').trim().slice(0, 80)
  if ('requirements' in out) {
    const q = out.requirements || {}
    const y = Number(q.minModelYear), r = Number(q.minDriverRating)
    const thisYear = new Date().getFullYear()
    out.requirements = {
      minModelYear: Number.isFinite(y) && y >= 1990 && y <= thisYear + 1 ? Math.round(y) : null,
      minDriverRating: Number.isFinite(r) && r > 0 && r <= 5 ? Math.round(r * 10) / 10 : null,
      allowedModels: (Array.isArray(q.allowedModels) ? q.allowedModels : String(q.allowedModels || '').split(','))
        .map((m: any) => String(m || '').trim()).filter(Boolean).slice(0, 50),
      note: String(q.note || '').trim().slice(0, 200),
    }
  }
  return out
}
