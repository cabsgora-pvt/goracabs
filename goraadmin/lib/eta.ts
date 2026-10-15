// ─────────────────────────────────────────────────────────────────────────────
// ETA engine — single source of truth for "how long until the driver is here".
//
// ── The model ────────────────────────────────────────────────────────────────
//
//     etaMin = crowKm x minPerKm(cell, hour, dayType) + PICKUP_OVERHEAD_MIN
//
// One learned factor, not two guessed ones. The previous engine computed
//
//     roadKm = crowKm x 1.4                  <- global constant, all of India
//     etaMin = roadKm / speed(cell, hour)    <- learned
//
// and fed itself a corrupted signal: on arrival it derived "observed speed" by
// dividing the PREDICTED road distance by the real elapsed time, so any error in
// that 1.4 was laundered into the learned speed and pushed the next prediction
// the wrong way.
//
// Learning minutes-per-crow-km fixes both. Detour and congestion are captured
// together, per area, per hour, from quantities we genuinely measure: real
// elapsed minutes over real crow-flies distance. Nothing is assumed.
//
// PICKUP_OVERHEAD_MIN covers the part that does not scale with distance — the
// last hundred metres, finding the gate, the rider walking out. Modelling it as
// a constant stops short pickups from being systematically under-promised.
//
// ── Where the numbers come from ──────────────────────────────────────────────
// EtaProfile rows, rebuilt by /api/cron/speed-profile from our own completed
// pickups, in tiers from exact bucket down to a fleet-wide row, each shrunk
// toward its parent by sample count. Lookup takes the most specific row that
// exists. On an empty database every tier is missing and DEFAULT_MIN_PER_KM
// applies, so this is safe from day one.
// ─────────────────────────────────────────────────────────────────────────────
import { distanceKm, type LatLng } from './geo'
import EtaProfile from '@/models/EtaProfile'
import Ride from '@/models/Ride'

export const ETA_CONFIG = {
  // ── The prediction ──
  // Minutes to cover one crow-flies km when nothing has been learned yet.
  // ~22 km/h through a ~1.4x detour ≈ 3.8 min per crow-km; rounded to 3.8.
  DEFAULT_MIN_PER_KM: 3.8,
  // Distance-independent cost of completing a pickup.
  PICKUP_OVERHEAD_MIN: 1.5,
  // Guard rails: one bad aggregation must never produce absurd ETAs.
  MIN_MIN_PER_KM: 1.0,   // 60 km/h door to door — implausibly fast in a city
  MAX_MIN_PER_KM: 12.0,  // 5 km/h — gridlock

  // ── Candidate filtering ──
  // A driver whose app has not pinged within this window is a ghost. The app
  // pings every 15 s, so this tolerates 6 consecutive misses. The old 5-minute
  // window let a driver whose app died 4 minutes ago define the advertised ETA
  // and still receive offers, which then simply timed out.
  LOCATION_FRESH_MS: 90 * 1000,
  // Slightly looser for the booking screen: showing a marginally stale ETA is
  // better than showing "no cabs" because a ping was dropped.
  LOCATION_FRESH_QUOTE_MS: 3 * 60 * 1000,
  MAX_PICKUP_RADIUS_KM: 15,
  // Beyond this we report "no driver" rather than a clamped, pretty, wrong
  // number. Applied identically at quote time and at accept time — these used
  // to disagree (45 vs 120), so an accepted ride could record a prediction the
  // quoting side would have refused to display.
  MAX_ETA_MIN: 45,
  MIN_ETA_MIN: 1,

  // ── Look-ahead ──
  // A driver two minutes from finishing a drop 200 m away is a better candidate
  // than one who just came online 10 km out, but the old filter excluded anyone
  // on a ride outright. Drivers finishing within this window are considered,
  // with their remaining trip time added to their pickup ETA.
  LOOKAHEAD_ENABLED: process.env.ETA_LOOKAHEAD !== '0',
  LOOKAHEAD_MAX_WAIT_MIN: 5,

  // ── Quoting ──
  // How many nearest drivers form the candidate pool per vehicle type.
  CANDIDATE_POOL: 5,
  // Quoted ETA = prediction + a buffer sized from this bucket's own measured
  // spread, capped here. This replaces the old QUOTE_RANK trick of advertising
  // the SECOND-best driver's ETA while dispatch offered the FIRST — which meant
  // the number shown and the driver sent were, by construction, different
  // people, and made prediction-vs-actual telemetry measure the wrong thing.
  MAX_QUOTE_BUFFER_MIN: 4,

  // ── Learning ──
  // Shrinkage strength: a bucket needs ~this many samples before it outweighs
  // its parent tier. Low enough that real local signal surfaces quickly.
  SHRINK_K: 10,
  // Rows below this are still written (shrinkage makes them safe) but are
  // flagged so the admin can tell a learned row from a mostly-inherited one.
  CONFIDENT_SAMPLES: 30,
}

// ── Time helpers ─────────────────────────────────────────────────────────────
// India-only product; the server TZ is not guaranteed to be IST, so bucket
// explicitly at UTC+05:30 rather than trusting getHours().
const IST_OFFSET_MS = 5.5 * 60 * 60 * 1000

export type DayType = 'weekday' | 'weekend'

export function istParts(d: Date = new Date()): { hour: number; dayType: DayType } {
  const ist = new Date(d.getTime() + IST_OFFSET_MS)
  const dow = ist.getUTCDay() // 0 = Sunday
  return {
    hour: ist.getUTCHours(),
    dayType: dow === 0 || dow === 6 ? 'weekend' : 'weekday',
  }
}

/**
 * Coarse time-of-day band. Traffic is far more similar within a band than
 * across one, so this is the first fallback when an exact hour is too sparse —
 * 09:00 borrows from the rest of the morning peak, not from 3am.
 */
export function hourBand(hour: number): number {
  if (hour < 6) return 0        // night
  if (hour < 10) return 1       // morning peak
  if (hour < 16) return 2       // midday
  if (hour < 21) return 3       // evening peak
  return 4                      // late evening
}

// ── Spatial bucketing ────────────────────────────────────────────────────────
// H3 res-8 equivalent (~0.75 km^2 per cell) implemented without a dependency.
// To move to real H3 later, swap the body for h3.latLngToCell(lat, lng, 8) —
// nothing else in the codebase parses the cell format.
const CELL_LAT_STEP = 0.0075 // ~833 m
const CELL_LNG_STEP = 0.008  // ~820 m across India's latitude band

export function geoCell(lat: number, lng: number): string {
  const y = Math.floor(lat / CELL_LAT_STEP)
  const x = Math.floor(lng / CELL_LNG_STEP)
  return `${y}:${x}`
}

/** ~6 km cell — a neighbourhood. The tier between "this street" and "India". */
export function coarseCell(lat: number, lng: number): string {
  const y = Math.floor(lat / (CELL_LAT_STEP * 8))
  const x = Math.floor(lng / (CELL_LNG_STEP * 8))
  return `${y}:${x}`
}

// ── Profile keys ─────────────────────────────────────────────────────────────
export type ProfileTier = 'exact' | 'band' | 'cell' | 'area' | 'global'

/** The lookup key for one tier. The cron writes these; the reader walks them. */
export function profileKey(
  tier: ProfileTier,
  p: { cell?: string; coarse?: string; hour?: number; band?: number; dayType?: DayType },
): string {
  switch (tier) {
    case 'exact': return `${p.cell}|${p.hour}|${p.dayType}`
    case 'band': return `${p.cell}|b${p.band}|${p.dayType}`
    case 'cell': return `${p.cell}`
    case 'area': return `${p.coarse}|b${p.band}`
    case 'global': return 'global'
  }
}

/** Most specific first — both the reader and the cron rely on this order. */
export const TIER_ORDER: ProfileTier[] = ['exact', 'band', 'cell', 'area', 'global']

// ── Factor lookup ────────────────────────────────────────────────────────────
export type EtaFactor = {
  /** Minutes per crow-flies km. */
  minPerKm: number
  /** Which tier supplied it — 'default' when nothing has been learned. */
  source: ProfileTier | 'default'
  /** Extra minutes to add to a QUOTED eta, from this bucket's measured spread. */
  bufferMin: number
  samples: number
}

const DEFAULT_FACTOR: EtaFactor = {
  minPerKm: ETA_CONFIG.DEFAULT_MIN_PER_KM,
  source: 'default',
  bufferMin: 2,
  samples: 0,
}

function clampFactor(v: number): number {
  if (!Number.isFinite(v) || v <= 0) return ETA_CONFIG.DEFAULT_MIN_PER_KM
  return Math.min(ETA_CONFIG.MAX_MIN_PER_KM, Math.max(ETA_CONFIG.MIN_MIN_PER_KM, v))
}

// Profiles only change when the cron runs, but this is on the hot path —
// driver/pending calls it every few seconds per online driver. Memoise per
// (cell, hour, dayType) so 500 online drivers cost ~1 query per cell per TTL.
const FACTOR_CACHE_TTL_MS = 10 * 60 * 1000
const factorCache = new Map<string, { value: EtaFactor; expiresAt: number }>()

/** Test seam — the cron clears this after a rebuild so new rows apply at once. */
export function clearEtaFactorCache(): void {
  factorCache.clear()
}

/**
 * Learned travel factor for a place and time.
 *
 * Walks the tiers most-specific-first and takes the first row present. Rows are
 * already shrunk toward their parent at write time, so no blending is needed
 * here and the read stays a single indexed query.
 */
export async function getEtaFactor(pickup: LatLng, when: Date = new Date()): Promise<EtaFactor> {
  const { hour, dayType } = istParts(when)
  const cell = geoCell(pickup.lat, pickup.lng)
  const coarse = coarseCell(pickup.lat, pickup.lng)
  const band = hourBand(hour)

  const ck = `${cell}|${hour}|${dayType}`
  const now = Date.now()
  const cached = factorCache.get(ck)
  if (cached && cached.expiresAt > now) return cached.value

  const remember = (v: EtaFactor) => {
    if (factorCache.size > 20000) factorCache.clear() // coarse but bounded
    factorCache.set(ck, { value: v, expiresAt: now + FACTOR_CACHE_TTL_MS })
    return v
  }

  try {
    const keys = TIER_ORDER.map(tier => ({
      tier,
      key: profileKey(tier, { cell, coarse, hour, band, dayType }),
    }))
    const rows: any[] = await EtaProfile.find({ $or: keys }).lean()
    if (!rows.length) return remember(DEFAULT_FACTOR)

    const byTier = new Map<string, any>(rows.map(r => [r.tier, r]))
    for (const tier of TIER_ORDER) {
      const row = byTier.get(tier)
      if (!row || row.minPerKm == null) continue
      const minPerKm = clampFactor(row.minPerKm)
      // Buffer = how much slower the 90th-percentile trip runs than the median,
      // over a typical 2 km pickup. Falls back to a modest constant.
      const spread = row.p90MinPerKm != null ? Math.max(0, row.p90MinPerKm - row.minPerKm) : null
      const bufferMin = spread != null
        ? Math.min(ETA_CONFIG.MAX_QUOTE_BUFFER_MIN, +(spread * 2).toFixed(1))
        : 2
      return remember({ minPerKm, source: tier, bufferMin, samples: row.samples || 0 })
    }
    return remember(DEFAULT_FACTOR)
  } catch {
    // Never let a profile lookup break a booking screen — and do not cache the
    // failure, so a transient DB blip cannot pin the default for 10 minutes.
    return DEFAULT_FACTOR
  }
}

// ── Distance ─────────────────────────────────────────────────────────────────
/** Crow-flies km. The model consumes this directly — no circuity constant. */
export function crowKm(a: LatLng, b: LatLng): number {
  return distanceKm(a, b)
}

/**
 * Approximate road km, for DISPLAY only ("2.4 km away").
 *
 * Derived from the learned factor rather than a fixed 1.4, by comparing this
 * bucket's minutes-per-km against a nominal urban road speed. Never used in the
 * prediction path, and never in a fare.
 */
const NOMINAL_ROAD_SPEED_KMPH = 24
export function displayRoadKm(crow: number, factor: EtaFactor): number {
  const impliedKm = (crow * factor.minPerKm / 60) * NOMINAL_ROAD_SPEED_KMPH
  // Road distance can never be shorter than the straight line.
  return +Math.max(crow, impliedKm).toFixed(1)
}

// ── ETA ──────────────────────────────────────────────────────────────────────
/**
 * Minutes to reach a pickup `crow` km away.
 *
 * Returns null past `maxMin` — callers must surface "no driver available"
 * rather than a clamped-but-wrong number.
 */
export function predictEtaMin(
  crow: number,
  factor: EtaFactor,
  opts: { maxMin?: number; buffered?: boolean } = {},
): number | null {
  if (!Number.isFinite(crow) || crow < 0) return null
  const maxMin = opts.maxMin ?? ETA_CONFIG.MAX_ETA_MIN
  const raw = crow * factor.minPerKm
    + ETA_CONFIG.PICKUP_OVERHEAD_MIN
    + (opts.buffered ? factor.bufferMin : 0)
  const min = Math.round(raw)
  if (min > maxMin) return null
  return Math.max(ETA_CONFIG.MIN_ETA_MIN, min)
}

// ── Driver availability ──────────────────────────────────────────────────────
/** Mongo fragment: approved, online, located, and pinged recently. */
export function availableDriverFilter(
  extra: Record<string, any> = {},
  freshMs: number = ETA_CONFIG.LOCATION_FRESH_MS,
) {
  return {
    status: 'approved',
    isOnline: true,
    currentLat: { $ne: null },
    currentLng: { $ne: null },
    locationUpdatedAt: { $gte: new Date(Date.now() - freshMs) },
    ...extra,
  }
}

/** What a driver is currently committed to, keyed by driver id. */
export type BusyRide = { status: string; dropLat?: number; dropLng?: number }

/**
 * Rides currently occupying a driver.
 *
 * Replaces the old boolean "is this driver busy". A driver finishing a drop
 * 200 m away was previously excluded outright while someone 10 km out stayed a
 * candidate; returning the trip lets rankCandidates work out when they will
 * actually be free and rank them on arrival time instead.
 *
 * Always pass `candidateIds` when the shortlist is known: it turns a scan of
 * every active ride on the platform into a bounded $in covered by the
 * {status, driverId} index.
 */
export async function driverBusyRides(candidateIds?: string[]): Promise<Map<string, BusyRide>> {
  const out = new Map<string, BusyRide>()
  try {
    if (candidateIds && candidateIds.length === 0) return out
    const query: any = { status: { $in: ['accepted', 'arrived', 'ongoing'] } }
    query.driverId = candidateIds?.length ? { $in: candidateIds } : { $ne: null }
    const rows: any[] = await Ride.find(query)
      .select('driverId status dropLat dropLng')
      .lean()
    for (const r of rows) {
      out.set(String(r.driverId), { status: r.status, dropLat: r.dropLat, dropLng: r.dropLng })
    }
  } catch {
    // On failure return an empty map rather than risk excluding everyone — the
    // atomic claim in /accept is what actually prevents double-booking.
  }
  return out
}

/**
 * Minutes until a busy driver can start a new pickup, or Infinity when they are
 * not a realistic candidate.
 *
 * Only an in-progress trip has a meaningful remaining time. A driver who has
 * accepted but not yet started is still heading to THEIR rider's pickup, so
 * they stay fully excluded.
 */
function waitUntilFreeMin(
  busy: BusyRide | undefined,
  driver: { currentLat?: number; currentLng?: number },
  factor: EtaFactor,
): number {
  if (!busy) return 0
  if (!ETA_CONFIG.LOOKAHEAD_ENABLED) return Infinity
  if (busy.status !== 'ongoing') return Infinity
  if (busy.dropLat == null || busy.dropLng == null) return Infinity
  if (driver.currentLat == null || driver.currentLng == null) return Infinity

  const remaining = crowKm(
    { lat: driver.currentLat, lng: driver.currentLng },
    { lat: busy.dropLat, lng: busy.dropLng },
  )
  const mins = remaining * factor.minPerKm
  return mins <= ETA_CONFIG.LOOKAHEAD_MAX_WAIT_MIN ? Math.round(mins) : Infinity
}

// ── Ranking ──────────────────────────────────────────────────────────────────
export type DriverCandidate = {
  id: string
  vehicleTypeName: string
  /** Approximate road km, for display. */
  km: number
  /** Total minutes until this driver reaches the pickup. */
  etaMin: number
  /** Minutes of that which are spent finishing a current trip. */
  waitMin: number
  // Driver position, carried so the traffic refinement pass can build its
  // origins list without a second driver lookup.
  lat: number
  lng: number
  // True once km/etaMin came from Distance Matrix rather than the model.
  trafficRefined?: boolean
}

export type EtaBounds = { maxRadiusKm?: number; maxEtaMin?: number }

/**
 * Filters a driver list to realistic pickup candidates and ranks them by ETA —
 * not raw distance, which is the whole point. Drivers whose wait exceeds the
 * look-ahead window are dropped, as is anyone beyond the radius or time bound.
 */
export function rankCandidates(
  drivers: any[],
  pickup: LatLng,
  factor: EtaFactor,
  busy: Map<string, BusyRide> = new Map(),
  bounds: EtaBounds = {},
): DriverCandidate[] {
  const maxKm = bounds.maxRadiusKm ?? ETA_CONFIG.MAX_PICKUP_RADIUS_KM
  const maxMin = bounds.maxEtaMin ?? ETA_CONFIG.MAX_ETA_MIN
  const out: DriverCandidate[] = []
  for (const d of drivers) {
    if (d.currentLat == null || d.currentLng == null) continue
    const waitMin = waitUntilFreeMin(busy.get(String(d._id)), d, factor)
    if (!Number.isFinite(waitMin)) continue          // busy and not finishing soon
    const crow = crowKm(pickup, { lat: d.currentLat, lng: d.currentLng })
    if (crow > maxKm) continue
    const travel = predictEtaMin(crow, factor, { maxMin })
    if (travel == null) continue
    const total = travel + waitMin
    if (total > maxMin) continue
    out.push({
      id: String(d._id),
      vehicleTypeName: d.selectedVehicleTypeName || '',
      km: displayRoadKm(crow, factor),
      etaMin: total,
      waitMin,
      lat: d.currentLat,
      lng: d.currentLng,
    })
  }
  return out.sort((a, b) => a.etaMin - b.etaMin || a.km - b.km)
}

// ── Traffic refinement ───────────────────────────────────────────────────────
// The model is geometric: it cannot see a jam, a one-way, a river or a railway
// line, so a driver 2 km away across a level crossing outranks one 3 km away on
// a clear road. Distance Matrix fixes exactly that, batched 25-origins-per-call
// and cached, but costs money per origin — so it refines only a shortlist, and
// only where it changes an outcome.
//
//   DISPATCH (on)  — decides who is actually offered the ride. One call per
//                    booking, highest value.
//   QUOTE    (off) — the per-vehicle ETA on the booking screen. Fires on every
//                    estimate, so the volume is far higher; opt in once you have
//                    watched the spend from DISPATCH alone.
export const MATRIX_REFINE = {
  DISPATCH: process.env.ETA_MATRIX_DISPATCH === '1',
  QUOTE: process.env.ETA_MATRIX_QUOTE === '1',
  // Capped at the 25-origin Distance Matrix limit so one shortlist is one call.
  TOP_N: Math.max(1, Math.min(25, Number(process.env.ETA_MATRIX_TOP_N) || 10)),
}

/**
 * Replaces the geometric estimate with real traffic-aware road distance and
 * duration for the top-K candidates, then re-sorts the whole list.
 *
 * Defensive at every step:
 *   - no Maps key, matrix failure, or a thrown import  → original list returned
 *   - individual origins Google could not route        → keep their model value
 *   - a refinement that would empty the list entirely  → original list returned
 *
 * That last guard matters: a refined ETA legitimately over the bound is real
 * information and that candidate should drop out, but ALL of them dropping is
 * far more likely a misconfigured key or a quota error than every driver in the
 * city being 45 minutes from one pickup.
 *
 * The import is dynamic because lib/distance-matrix.ts imports geoCell from
 * this module; a static import here would close that cycle. It also means the
 * module is never loaded when refinement is off.
 */
export async function refineCandidatesWithTraffic(
  candidates: DriverCandidate[],
  pickup: LatLng,
  bounds: EtaBounds = {},
  // Which candidates to spend calls on. Defaults to the global top-K, which is
  // right for dispatch (one ride, one vehicle type). The quote path passes an
  // explicit set instead, because there the list spans several vehicle types and
  // a global top-K would refine only the closest type.
  only?: Set<string>,
): Promise<DriverCandidate[]> {
  if (candidates.length === 0) return candidates

  const pick = only
    ? (c: DriverCandidate) => only.has(c.id)
    : (_c: DriverCandidate, i: number) => i < MATRIX_REFINE.TOP_N
  const head: DriverCandidate[] = []
  const tail: DriverCandidate[] = []
  candidates.forEach((c, i) => (pick(c, i) && head.length < MATRIX_REFINE.TOP_N ? head : tail).push(c))
  if (head.length === 0) return candidates

  let legs: Array<{ km: number; min: number } | null>
  try {
    const { matrixToDestination } = await import('./distance-matrix')
    legs = await matrixToDestination(head.map(c => ({ lat: c.lat, lng: c.lng })), pickup)
  } catch (e) {
    console.error('[eta] traffic refinement unavailable', e)
    return candidates
  }

  const maxKm = bounds.maxRadiusKm ?? ETA_CONFIG.MAX_PICKUP_RADIUS_KM
  const maxMin = bounds.maxEtaMin ?? ETA_CONFIG.MAX_ETA_MIN

  const refined: DriverCandidate[] = []
  let changed = false
  head.forEach((c, i) => {
    const leg = legs[i]
    // Google routed but returned a zero-length/zero-time leg — not usable.
    if (!leg || leg.min <= 0 || leg.km <= 0) { refined.push(c); return }
    changed = true
    // A measured drive time still has to carry the pickup overhead and any
    // wait for the driver's current trip to end.
    const total = Math.round(leg.min + ETA_CONFIG.PICKUP_OVERHEAD_MIN) + c.waitMin
    if (leg.km > maxKm || total > maxMin) return // genuinely out of range now
    refined.push({
      ...c,
      km: +leg.km.toFixed(1),
      etaMin: Math.max(ETA_CONFIG.MIN_ETA_MIN, total),
      trafficRefined: true,
    })
  })

  if (!changed) return candidates                       // nothing came back
  const merged = [...refined, ...tail]
  if (merged.length === 0) return candidates            // total wipe — distrust it
  return merged.sort((a, b) => a.etaMin - b.etaMin || a.km - b.km)
}

// ── Quoting ──────────────────────────────────────────────────────────────────
export type VehicleEta = { km: number; min: number; available: number }

/**
 * Advertised ETA per vehicle type, from an already ETA-sorted candidate list.
 *
 * Quotes the BEST candidate — the same driver dispatch will offer — plus a
 * buffer sized from that bucket's own measured spread. The previous engine
 * advertised the second-best driver's ETA as a crude proxy for decline rate,
 * which meant the number shown and the driver sent were different people by
 * construction, and made prediction-vs-actual telemetry meaningless.
 */
export function bestEtaByVehicleType(
  candidates: DriverCandidate[],
  factor: EtaFactor,
): Map<string, VehicleEta> {
  const grouped = new Map<string, DriverCandidate[]>()
  for (const c of candidates) {
    if (!c.vehicleTypeName) continue
    const list = grouped.get(c.vehicleTypeName)
    if (list) list.push(c)
    else grouped.set(c.vehicleTypeName, [c])
  }

  const out = new Map<string, VehicleEta>()
  for (const [type, list] of grouped) {
    const best = list[0]
    // Traffic-refined legs are measured, not modelled, so they need much less
    // padding than a geometric estimate.
    const buffer = best.trafficRefined ? Math.min(1, factor.bufferMin) : factor.bufferMin
    out.set(type, {
      km: best.km,
      min: Math.max(ETA_CONFIG.MIN_ETA_MIN, Math.round(best.etaMin + buffer)),
      available: list.length,
    })
  }
  return out
}

/**
 * One-call helper for the booking screens: load fresh, non-busy drivers and
 * return the per-vehicle-type ETA map. `extraFilter` scopes by zone/service.
 */
export async function etaByVehicleType(
  DriverModel: any,
  pickup: LatLng,
  extraFilter: Record<string, any> = {},
  bounds: EtaBounds = {},
  when: Date = new Date(),
): Promise<Map<string, VehicleEta>> {
  const [factor, drivers] = await Promise.all([
    getEtaFactor(pickup, when),
    DriverModel.find(availableDriverFilter(extraFilter, ETA_CONFIG.LOCATION_FRESH_QUOTE_MS))
      .select('selectedVehicleTypeName currentLat currentLng')
      .lean() as Promise<any[]>,
  ])
  // Scope the busy lookup to the drivers we actually care about.
  const busy = await driverBusyRides(drivers.map((d: any) => String(d._id)))
  let ranked = rankCandidates(drivers, pickup, factor, busy, bounds)

  // Refining here is opt-in: this runs on every fare estimate, not once per
  // booking. Spend the calls on the pool that actually sets each type's
  // advertised ETA — the top CANDIDATE_POOL of EVERY vehicle type — rather than
  // the global top-K, which would refine only the nearest type.
  if (MATRIX_REFINE.QUOTE) {
    const perType = new Map<string, number>()
    const only = new Set<string>()
    for (const c of ranked) {
      const seen = perType.get(c.vehicleTypeName) || 0
      if (seen >= ETA_CONFIG.CANDIDATE_POOL) continue
      perType.set(c.vehicleTypeName, seen + 1)
      only.add(c.id)
    }
    ranked = await refineCandidatesWithTraffic(ranked, pickup, bounds, only)
  }
  return bestEtaByVehicleType(ranked, factor)
}
