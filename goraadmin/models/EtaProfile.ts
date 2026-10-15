import mongoose, { Schema } from 'mongoose'

// ─────────────────────────────────────────────────────────────────────────────
// Learned pickup-leg travel model.
//
// Replaces SpeedProfile, which stored a km/h figure that the predictor then had
// to combine with a hardcoded global circuity constant (1.4) to turn a
// crow-flies distance into minutes. That had two problems:
//
//   1. Detour varies enormously by area — an old-city lane and a ring road do
//      not share a multiplier — but circuity was one number for all of India.
//   2. The learner divided by the PREDICTED road distance, so whenever the
//      circuity guess was wrong for a cell that error was absorbed into the
//      "speed", which then compensated in the wrong direction on the next
//      prediction.
//
// This model learns minutes-per-crow-km directly. One number, measured from
// quantities we actually observe (real elapsed minutes ÷ real crow distance),
// so detour and congestion are captured together, per area, per time of day.
//
// TIERS + SHRINKAGE
// A single (cell, hour, dayType) bucket needs a lot of rides before its median
// means anything, and a hard sample floor gives a cliff: 19 samples = fall all
// the way back to a nationwide default. Instead the cron writes several tiers,
// coarsest first, and shrinks each toward its parent by sample count:
//
//     estimate = (n * own + K * parent) / (n + K)
//
// A bucket with 3 observations leans almost entirely on its parent; one with
// 300 stands on its own. There is no cliff, and the model is useful from the
// first week rather than after ~960 rides per cell.
//
// Rebuilt by POST /api/cron/speed-profile (scheduled in ecosystem.config.js).
// ─────────────────────────────────────────────────────────────────────────────

const EtaProfileSchema = new Schema({
  // Which resolution this row describes. Lookup walks these most-specific first:
  //   exact  → cell + hour + dayType
  //   band   → cell + hour-band + dayType
  //   cell   → cell (all times)
  //   area   → ~6 km coarse cell + hour-band
  //   global → single fleet-wide row
  tier: {
    type: String,
    enum: ['exact', 'band', 'cell', 'area', 'global'],
    required: true,
  },
  // Composite lookup key, shaped per tier by lib/eta.ts profileKey().
  key: { type: String, required: true },

  // Denormalised components, for querying and for the admin to read.
  cell: String,
  hour: { type: Number, min: 0, max: 23 },
  hourBand: { type: Number, min: 0, max: 4 },
  dayType: { type: String, enum: ['weekday', 'weekend'] },

  // ── The prediction itself ──
  // Minutes to cover one crow-flies km, including detour. Already shrunk toward
  // this row's parent tier, so it can be used directly.
  minPerKm: { type: Number, required: true },
  // Same figure before shrinkage — kept so the effect of shrinkage is visible.
  rawMinPerKm: Number,

  // ── Reliability ──
  // Spread between the median and the 90th percentile, in minutes per km. Used
  // to size the buffer added to a quoted ETA, so the promise a rider sees
  // reflects how noisy this bucket actually is rather than a flat fudge factor.
  p90MinPerKm: Number,
  // Median absolute error of predictions made in this bucket, in minutes.
  medianAbsErrorMin: Number,

  samples: { type: Number, default: 0 },
  lastComputedAt: Date,
}, { timestamps: true })

// One row per tier+key. The cron upserts against this.
EtaProfileSchema.index({ tier: 1, key: 1 }, { unique: true })

export default mongoose.models.EtaProfile || mongoose.model('EtaProfile', EtaProfileSchema)
