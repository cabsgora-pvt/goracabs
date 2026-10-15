export const dynamic = 'force-dynamic'
import { NextRequest } from 'next/server'
import { connectDB } from '@/lib/mongodb'
import Ride from '@/models/Ride'
import EtaProfile from '@/models/EtaProfile'
import { requireAuth } from '@/lib/auth'
import {
  geoCell, coarseCell, hourBand, istParts, profileKey, clearEtaFactorCache,
  ETA_CONFIG, type DayType, type ProfileTier,
} from '@/lib/eta'
import { withCors, corsOptions } from '@/lib/cors'

export async function OPTIONS() { return corsOptions() }

// ─────────────────────────────────────────────────────────────────────────────
// Rebuilds EtaProfile from our own completed pickups.
//
// This is the learner half of the ETA system: /arrived records minutes-per-crow-km
// for each real pickup, and this job turns those observations into a tiered,
// shrunk model the predictor can read in one indexed query.
//
// ── Why tiers + shrinkage rather than a sample floor ──
// The previous version wrote one row per (cell, hour, dayType) and refused to
// write it below 20 samples. With 24 hours x 2 day types that is 48 buckets per
// ~0.75 km^2 cell — roughly 960 completed pickups per cell before ANY of it was
// usable, and until then every ETA in that area fell back to a nationwide
// constant. For a new city that threshold is never reached.
//
// Instead this computes five nested tiers, coarsest first, and shrinks each
// toward its parent by sample count:
//
//     estimate = (n * own + K * parent) / (n + K)
//
// A bucket with 3 observations is ~77% parent; one with 300 is ~97% its own.
// Every tier is written, so the reader always finds something, and the model
// starts contributing from the first day of real traffic instead of month three.
//
// Auth: admin token, or CRON_SECRET via `x-cron-secret` for a scheduler.
// Scheduled daily in ecosystem.config.js. Safe to run repeatedly — it is a full
// recompute, not an append.
// ─────────────────────────────────────────────────────────────────────────────

const DEFAULT_LOOKBACK_DAYS = 28

function quantile(sorted: number[], q: number): number {
  if (!sorted.length) return 0
  const pos = (sorted.length - 1) * q
  const lo = Math.floor(pos)
  const hi = Math.ceil(pos)
  if (lo === hi) return sorted[lo]
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo)
}

function median(sorted: number[]): number {
  return quantile(sorted, 0.5)
}

/** Drop samples outside 1.5 x IQR — one stuck GPS should not move a bucket. */
function withoutOutliers(values: number[]): number[] {
  if (values.length < 4) return [...values].sort((a, b) => a - b)
  const s = [...values].sort((a, b) => a - b)
  const q1 = quantile(s, 0.25)
  const q3 = quantile(s, 0.75)
  const iqr = q3 - q1
  const lo = q1 - 1.5 * iqr
  const hi = q3 + 1.5 * iqr
  return s.filter(v => v >= lo && v <= hi)
}

/** Empirical-Bayes blend toward the parent tier. */
function shrink(own: number, n: number, parent: number): number {
  const k = ETA_CONFIG.SHRINK_K
  return (n * own + k * parent) / (n + k)
}

type Bucket = {
  tier: ProfileTier
  key: string
  cell?: string
  hour?: number
  hourBand?: number
  dayType?: DayType
  values: number[]
  errors: number[]
  /** Key of the tier above, for shrinkage. 'global' has none. */
  parentKey: string | null
  parentTier: ProfileTier | null
}

async function handle(req: NextRequest) {
  try {
    const secret = process.env.CRON_SECRET
    const headerSecret = req.headers.get('x-cron-secret')
    const authorised = (secret && headerSecret === secret) || !!requireAuth(req)
    if (!authorised) return withCors({ error: 'Unauthorized' }, 401)

    const days = Math.max(1, Math.min(180, Number(req.nextUrl.searchParams.get('days')) || DEFAULT_LOOKBACK_DAYS))
    const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000)

    await connectDB()

    const rides: any[] = await Ride.find({
      observedMinPerKm: { $ne: null, $gt: 0 },
      arrivedAt: { $gte: since },
      pickupLat: { $ne: null },
      pickupLng: { $ne: null },
    }).select('pickupLat pickupLng acceptedAt observedMinPerKm etaErrorMin').lean()

    // ── Bucket every observation into all five tiers at once ──
    const buckets = new Map<string, Bucket>()
    const add = (b: Omit<Bucket, 'values' | 'errors'>, value: number, err: number | null) => {
      const id = `${b.tier}::${b.key}`
      let e = buckets.get(id)
      if (!e) { e = { ...b, values: [], errors: [] }; buckets.set(id, e) }
      e.values.push(value)
      if (err != null) e.errors.push(Math.abs(err))
    }

    for (const r of rides) {
      if (!r.acceptedAt) continue
      const { hour, dayType } = istParts(new Date(r.acceptedAt))
      const band = hourBand(hour)
      const cell = geoCell(r.pickupLat, r.pickupLng)
      const coarse = coarseCell(r.pickupLat, r.pickupLng)
      const v = r.observedMinPerKm
      const err = r.etaErrorMin ?? null

      const kExact = profileKey('exact', { cell, hour, dayType })
      const kBand = profileKey('band', { cell, band, dayType })
      const kCell = profileKey('cell', { cell })
      const kArea = profileKey('area', { coarse, band })
      const kGlobal = profileKey('global', {})

      add({ tier: 'exact', key: kExact, cell, hour, hourBand: band, dayType, parentTier: 'band', parentKey: kBand }, v, err)
      add({ tier: 'band', key: kBand, cell, hourBand: band, dayType, parentTier: 'cell', parentKey: kCell }, v, err)
      add({ tier: 'cell', key: kCell, cell, parentTier: 'area', parentKey: kArea }, v, err)
      add({ tier: 'area', key: kArea, hourBand: band, parentTier: 'global', parentKey: kGlobal }, v, err)
      add({ tier: 'global', key: kGlobal, parentTier: null, parentKey: null }, v, err)
    }

    // ── Resolve coarsest-first so each tier's parent is already final ──
    const resolved = new Map<string, number>()   // "tier::key" → shrunk minPerKm
    const order: ProfileTier[] = ['global', 'area', 'cell', 'band', 'exact']
    const rows: any[] = []

    for (const tier of order) {
      for (const b of buckets.values()) {
        if (b.tier !== tier) continue
        const clean = withoutOutliers(b.values)
        if (!clean.length) continue
        const own = median(clean)
        const p90 = quantile(clean, 0.9)

        const parent = b.parentKey && b.parentTier
          ? resolved.get(`${b.parentTier}::${b.parentKey}`) ?? ETA_CONFIG.DEFAULT_MIN_PER_KM
          : ETA_CONFIG.DEFAULT_MIN_PER_KM

        // The global tier has no parent to borrow from; it IS the parent.
        const value = tier === 'global' ? own : shrink(own, clean.length, parent)
        resolved.set(`${b.tier}::${b.key}`, value)

        const errSorted = [...b.errors].sort((a, c) => a - c)
        rows.push({
          filter: { tier: b.tier, key: b.key },
          set: {
            tier: b.tier,
            key: b.key,
            cell: b.cell,
            hour: b.hour,
            hourBand: b.hourBand,
            dayType: b.dayType,
            minPerKm: +value.toFixed(3),
            rawMinPerKm: +own.toFixed(3),
            p90MinPerKm: +p90.toFixed(3),
            medianAbsErrorMin: errSorted.length ? +median(errSorted).toFixed(2) : null,
            samples: clean.length,
            lastComputedAt: new Date(),
          },
        })
      }
    }

    // Replace wholesale: a bucket that no longer has data should disappear
    // rather than linger with a stale figure from a month ago.
    await EtaProfile.deleteMany({})
    if (rows.length) {
      await EtaProfile.bulkWrite(rows.map(r => ({
        updateOne: { filter: r.filter, update: { $set: r.set }, upsert: true },
      })))
    }

    // New rows must take effect now, not up to 10 minutes later.
    clearEtaFactorCache()

    // ── Fleet-wide accuracy snapshot, so the effect of this job is visible ──
    const allErrors = rides
      .map(r => r.etaErrorMin)
      .filter((v: any) => v != null)
      .map(Math.abs)
      .sort((a: number, b: number) => a - b)

    const byTier: Record<string, number> = {}
    for (const r of rows) byTier[r.set.tier] = (byTier[r.set.tier] || 0) + 1
    const confident = rows.filter(r => r.set.samples >= ETA_CONFIG.CONFIDENT_SAMPLES).length

    return withCors({
      success: true,
      lookbackDays: days,
      ridesConsidered: rides.length,
      profilesWritten: rows.length,
      profilesByTier: byTier,
      confidentProfiles: confident,
      globalMinPerKm: resolved.get('global::global') ?? null,
      accuracy: {
        medianAbsErrorMin: allErrors.length ? +median(allErrors).toFixed(2) : null,
        p90AbsErrorMin: allErrors.length ? +quantile(allErrors, 0.9).toFixed(2) : null,
        sampleSize: allErrors.length,
      },
    })
  } catch (e: any) {
    return withCors({ error: e.message || 'Server error' }, 500)
  }
}

export const POST = handle
export const GET = handle
