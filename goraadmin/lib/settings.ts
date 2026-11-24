import fs from 'fs'
import path from 'path'

// ─────────────────────────────────────────────────────────────────────────────
// Platform settings. The admin panel writes them to Mongo (Settings{key:'global'});
// data/settings.json is the legacy store. They had diverged, so the source of
// truth is now Mongo, with the JSON file used only for fields Mongo leaves empty
// (null / undefined / '') — e.g. a Maps key that was only ever saved to the file.
//
//   getSettingsAsync()  Mongo-first merged view, cached in memory for CACHE_MS.
//   getSettings()       sync, for legacy callers: the last merged view if one is
//                       cached (and refreshes it in the background), else the
//                       JSON file. Prefer the async variant in new code.
//   invalidateSettingsCache()  call after writing Settings.
// ─────────────────────────────────────────────────────────────────────────────

const settingsPath = path.join(process.cwd(), 'data', 'settings.json')
const CACHE_MS = 30_000

let cache: { value: any; at: number } | null = null
let inflight: Promise<any> | null = null

function readFile(): any {
  try { return JSON.parse(fs.readFileSync(settingsPath, 'utf-8')) } catch { return {} }
}

function isEmpty(v: any) { return v === undefined || v === null || v === '' }
function isPlainObject(v: any) {
  return !!v && typeof v === 'object' && !Array.isArray(v) && !(v instanceof Date) && !v._bsontype
}

/** base ⊕ over: values from `over` win unless empty; nested objects merge. */
function mergeSettings(base: any, over: any): any {
  if (!isPlainObject(over)) return isEmpty(over) ? base : over
  const out: any = isPlainObject(base) ? { ...base } : {}
  for (const [k, v] of Object.entries(over)) {
    if (isPlainObject(v)) out[k] = mergeSettings(out[k], v)
    else if (!isEmpty(v)) out[k] = v
  }
  return out
}

async function load(): Promise<any> {
  const file = readFile()
  let db: any = null
  try {
    const { connectDB } = await import('./mongodb')
    const Settings = (await import('@/models/Settings')).default as any
    await connectDB()
    db = await Settings.findOne({ key: 'global' }).lean()
  } catch {
    // Mongo unreachable: the file (and the last cache) stand in.
    if (cache) return cache.value
  }
  if (db) {
    const { _id, __v, createdAt, updatedAt, key, ...rest } = db
    return mergeSettings(file, rest)
  }
  return file
}

export async function getSettingsAsync(): Promise<any> {
  if (cache && Date.now() - cache.at < CACHE_MS) return cache.value
  if (!inflight) {
    inflight = load()
      .then(v => { cache = { value: v, at: Date.now() }; return v })
      .finally(() => { inflight = null })
  }
  return inflight
}

export function getSettings(): any {
  if (cache) {
    if (Date.now() - cache.at >= CACHE_MS) getSettingsAsync().catch(() => {})
    return cache.value
  }
  getSettingsAsync().catch(() => {})
  return readFile()
}

export function invalidateSettingsCache() { cache = null }
