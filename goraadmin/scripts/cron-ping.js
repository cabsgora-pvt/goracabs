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
const paths = process.argv.slice(2).filter(Boolean)

async function ping(p) {
  const url = BASE + (p.startsWith('/') ? p : '/' + p)
  const ctrl = new AbortController()
  const timer = setTimeout(() => ctrl.abort(), TIMEOUT_MS)
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

async function main() {
  if (!paths.length) {
    console.error('[cron-ping] usage: node scripts/cron-ping.js /api/cron/<job> [...]')
    process.exit(2)
  }
  if (!SECRET || SECRET.startsWith('change-me')) {
    console.error('[cron-ping] CRON_SECRET is unset or still the placeholder — refusing to run. Add it to .env.local.')
    process.exit(1)
  }
  let ok = true
  for (const p of paths) ok = (await ping(p)) && ok
  // exitCode, not process.exit(): exiting while fetch sockets are still closing
  // trips a libuv assertion on Windows. The process ends once sockets close.
  process.exitCode = ok ? 0 : 1
}

main()
