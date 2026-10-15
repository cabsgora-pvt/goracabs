#!/usr/bin/env node
// ─────────────────────────────────────────────────────────────────────────────
// Scheduled runner for /api/cron/speed-profile.
//
// Why this file exists: the ETA engine (lib/eta.ts) looks up a learned speed
// per (cell, hour, dayType) from the SpeedProfile collection, and that
// collection is only ever written by /api/cron/speed-profile. Nothing was
// calling it — no vercel.json, no crontab, and ecosystem.config.js started only
// the Next server. So SpeedProfile stayed empty and getSpeedKmph() fell through
// to DEFAULT_SPEED_KMPH (22) on every single request. Peak-hour and 3am ETAs
// were identical, and every line of the learner was dead code.
//
// PM2 runs this on a schedule (see ecosystem.config.js → goraadmin-speed-cron).
// The job is a full recompute, not an append, so running it twice is harmless.
//
// Exits non-zero on failure so `pm2 logs` and the exit code both show it.
// ─────────────────────────────────────────────────────────────────────────────
const path = require('path')
const fs = require('fs')

// PM2 does not load .env.local for us, and the app itself is the only other
// reader of these values — so parse it here rather than duplicating config.
function loadEnvLocal() {
  const file = path.join(__dirname, '..', '.env.local')
  if (!fs.existsSync(file)) return
  for (const raw of fs.readFileSync(file, 'utf8').split('\n')) {
    const line = raw.trim()
    if (!line || line.startsWith('#')) continue
    const eq = line.indexOf('=')
    if (eq === -1) continue
    const key = line.slice(0, eq).trim()
    if (process.env[key] !== undefined) continue
    process.env[key] = line.slice(eq + 1).trim()
  }
}

loadEnvLocal()

const BASE = process.env.CRON_TARGET_URL || 'http://127.0.0.1:3000'
const SECRET = process.env.CRON_SECRET || ''
// 28 days matches the route default; override with LOOKBACK_DAYS if a city has
// only just launched and you want a shorter, more current window.
const DAYS = process.env.SPEED_PROFILE_DAYS || '28'

async function main() {
  if (!SECRET || SECRET.startsWith('change-me')) {
    console.error('[speed-profile-cron] CRON_SECRET is unset or still the placeholder — refusing to run.')
    process.exit(1)
  }

  const url = `${BASE}/api/cron/speed-profile?days=${encodeURIComponent(DAYS)}`
  const started = Date.now()

  const res = await fetch(url, {
    method: 'POST',
    headers: { 'x-cron-secret': SECRET },
  })
  const body = await res.json().catch(() => ({}))

  if (!res.ok) {
    console.error(`[speed-profile-cron] HTTP ${res.status}`, body.error || body)
    process.exit(1)
  }

  const a = body.accuracy || {}
  const tiers = body.profilesByTier || {}
  console.log(
    `[speed-profile-cron] ok in ${Date.now() - started}ms — ` +
    `rides=${body.ridesConsidered} profiles=${body.profilesWritten} ` +
    `(${Object.entries(tiers).map(([k, v]) => `${k}:${v}`).join(' ')}) ` +
    `confident=${body.confidentProfiles} globalMinPerKm=${body.globalMinPerKm ?? 'n/a'} ` +
    `medianAbsErr=${a.medianAbsErrorMin ?? 'n/a'}min p90AbsErr=${a.p90AbsErrorMin ?? 'n/a'}min ` +
    `(n=${a.sampleSize ?? 0})`
  )

  // A healthy install writes profiles once it has traffic. Say so loudly while
  // it does not, because the symptom (every ETA on the flat default factor) is
  // invisible from the outside.
  if (body.profilesWritten === 0) {
    console.warn(
      '[speed-profile-cron] no profiles written — every ETA is still using ' +
      'DEFAULT_MIN_PER_KM. This is expected until rides start recording ' +
      'observedMinPerKm at /arrived.'
    )
  }
}

main().catch(e => {
  console.error('[speed-profile-cron] failed', e)
  process.exit(1)
})
