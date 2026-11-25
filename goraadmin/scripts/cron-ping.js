#!/usr/bin/env node
// ─────────────────────────────────────────────────────────────────────────────
// Minimal scheduled pinger: POSTs to one or more /api/cron/* endpoints with the
// x-cron-secret header and exits. No dependencies (Node 18+ global fetch).
//
//   node scripts/cron-ping.js /api/cron/notifications [/api/cron/dispatch ...]
//
// PM2 runs it every minute (ecosystem.config.js → goraadmin-cron-*), using the
// same one-shot pattern as scripts/speed-profile-cron.js: autorestart:false +
// cron_restart. CRON_SECRET is read from the environment or from .env.local
// (PM2 does not load .env.local) — it MUST be set in the server's .env.local,
// the app checks the same value.
//
// A 404 is logged and tolerated (exit 0): an endpoint may not be deployed yet
// (e.g. /api/cron/dispatch). Any other non-2xx or a network error exits 1.
//
// Sub-minute cadence: `--repeat N --every S` (or env CRON_REPEAT / CRON_EVERY_SEC) pings N times, S seconds apart,
// within this one run (PM2 cron cannot go below a minute). The dispatch pinger
// uses --repeat 4 --every 15 → every 15 s. A round that would start later than
// its slot (the previous one ran long) is skipped, rounds never overlap, and
// each ping's timeout is capped below the interval, so a run always ends inside
// its minute.
// ─────────────────────────────────────────────────────────────────────────────
const path = require('path')
const fs = require('fs')

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
    let val = line.slice(eq + 1).trim()
    if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) val = val.slice(1, -1)
    process.env[key] = val
  }
}

loadEnvLocal()

const BASE = (process.env.CRON_TARGET_URL || 'http://127.0.0.1:3000').replace(/\/+$/, '')
const SECRET = process.env.CRON_SECRET || ''
const TIMEOUT_MS = Number(process.env.CRON_TIMEOUT_MS || 50_000)
/** argv → { paths, repeat, everyMs }. */
function parseArgs(argv, env = process.env) {
  const out = { paths: [], repeat: 1, everyMs: 15_000 }
  // Defaults from the environment (PM2 entry env: CRON_REPEAT / CRON_EVERY_SEC).
  const er = Number(env.CRON_REPEAT), ee = Number(env.CRON_EVERY_SEC)
  if (Number.isInteger(er) && er >= 1 && er <= 12) out.repeat = er
  if (Number.isFinite(ee) && ee >= 1 && ee <= 60) out.everyMs = Math.round(ee * 1000)
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]
    const m = /^--(repeat|every)(?:=(.*))?$/.exec(a)
    if (m) {
      const v = m[2] !== undefined ? m[2] : argv[++i]
      const n = Number(v)
      if (m[1] === 'repeat' && Number.isInteger(n) && n >= 1 && n <= 12) out.repeat = n
      if (m[1] === 'every' && Number.isFinite(n) && n >= 1 && n <= 60) out.everyMs = Math.round(n * 1000)
    } else if (a) out.paths.push(a)
  }
  // N rounds must fit inside the minute PM2 gives the run.
  while (out.repeat > 1 && (out.repeat - 1) * out.everyMs >= 60_000) out.repeat--
  return out
}

/** Start offsets (ms from the run's start) of each round. */
function planRuns(repeat, everyMs) {
  return Array.from({ length: Math.max(1, repeat) }, (_, i) => i * everyMs)
}

const ARGS = parseArgs(process.argv.slice(2))
const paths = ARGS.paths

async function ping(p) {
  const url = BASE + (p.startsWith('/') ? p : '/' + p)
  const ctrl = new AbortController()
  const timer = setTimeout(() => ctrl.abort(), pingTimeoutMs())
  const started = Date.now()
  try {
    const res = await fetch(url, { method: 'POST', headers: { 'x-cron-secret': SECRET }, signal: ctrl.signal })
    const text = await res.text().catch(() => '')
    const ms = Date.now() - started
    if (res.status === 404) {
      console.warn(`[cron-ping] ${p} → 404 (endpoint not deployed yet), skipping`)
      return true
    }
    if (!res.ok) {
      console.error(`[cron-ping] ${p} → HTTP ${res.status} in ${ms}ms ${text.slice(0, 300)}`)
      return false
    }
    console.log(`[cron-ping] ${p} → ${res.status} in ${ms}ms ${text.slice(0, 200)}`)
    return true
  } catch (e) {
    console.error(`[cron-ping] ${p} failed: ${e && e.name === 'AbortError' ? 'timeout' : e && e.message}`)
    return false
  } finally {
    clearTimeout(timer)
  }
}

function pingTimeoutMs() {
  return ARGS.repeat > 1 ? Math.min(TIMEOUT_MS, Math.max(1_000, ARGS.everyMs - 1_000)) : TIMEOUT_MS
}

/**
 * Runs `round` at each planned offset. Skips a round whose slot has already
 * passed by more than half an interval (the previous round overran).
 * `clock`/`sleep` are injectable for tests.
 */
async function runRounds(round, repeat, everyMs, clock = Date.now, sleep = ms => new Promise(r => setTimeout(r, ms))) {
  const start = clock()
  let ok = true
  let ran = 0
  for (const offset of planRuns(repeat, everyMs)) {
    const wait = start + offset - clock()
    if (wait > 0) await sleep(wait)
    else if (-wait > everyMs / 2 && offset > 0) continue
    ok = (await round()) && ok
    ran++
  }
  return { ok, ran }
}

async function main() {
  if (!paths.length) {
    console.error('[cron-ping] usage: node scripts/cron-ping.js /api/cron/<job> [...]')
    process.exit(2)
  }
  if (!SECRET || SECRET.startsWith('change-me')) {
    console.error('[cron-ping] CRON_SECRET is unset or still the placeholder — refusing to run. Add it to .env.local.')
    process.exit(1)
  }
  const { ok } = await runRounds(async () => {
    let good = true
    for (const p of paths) good = (await ping(p)) && good
    return good
  }, ARGS.repeat, ARGS.everyMs)
  // exitCode, not process.exit(): exiting while fetch sockets are still closing
  // trips a libuv assertion on Windows. The process ends once sockets close.
  process.exitCode = ok ? 0 : 1
}

if (require.main === module) main()
module.exports = { parseArgs, planRuns, runRounds }
