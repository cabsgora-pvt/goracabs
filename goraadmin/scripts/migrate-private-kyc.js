#!/usr/bin/env node
// ─────────────────────────────────────────────────────────────────────────────
// Move KYC files that are still public (/uploads/...) into private storage.
//
// Before private uploads existed, driver documents, face photos and riders'
// ID photos were saved under public/uploads and are readable by anyone who
// has (or guesses) the URL. This script moves each such file to the private
// directory under a NEW random name, creates the Upload row the private file
// route needs (GET /api/files/<name>: models/Upload, lib/private-files) and
// rewrites every stored reference to /api/files/<name>.
//
// Fields migrated:
//   drivers.documents[].fileUrl / frontUrl / backUrl     (owner: that driver)
//   drivers.faceReferencePhotoUrl                         (owner: that driver)
//   faceverifications.photoUrl                            (owner: its driverId)
//   users.idPhotoUrl                                      (owner: that rider)
// Profile pictures, vehicle photos and payment QRs stay public on purpose.
//
// Usage (from the goraadmin directory):
//   node scripts/migrate-private-kyc.js                 DRY RUN: counts + sample, changes nothing
//   node scripts/migrate-private-kyc.js --apply         do it; writes a JSON log
//   node scripts/migrate-private-kyc.js --rollback <log.json>
// Options:
//   --uploads-dir <dir>   public uploads dir   (default ./public/uploads)
//   --private-dir <dir>   private uploads dir  (default ./data/private-uploads)
//   --log <file>          log path for --apply (default <private-dir>/../kyc-migration-<time>.json)
//   --env <file>          env file with MONGODB_URI (default ./.env.local; MONGODB_URI in the
//                         environment wins)
//   --limit <n>           migrate at most n files this run (the rest on the next run)
//   --only <id,id,...>    only these drivers / riders (by _id) — a pilot run
//
// Safety:
//   • Idempotent and resumable. Each new Upload row carries migratedFrom: <old
//     file name>, so a re-run (or a run after a crash) reuses the same new name
//     instead of copying the file again; a reference already on /api/files is
//     never touched. Per file the order is: Upload row → log entry → move the
//     file → rewrite references; a crash at any point is finished by the next run.
//   • A file missing from disk is reported and its references are left alone.
//   • The log records every rewritten reference with its exact old value, so
//     --rollback restores it (absolute URLs included), moves the file back to
//     its old name and removes the Upload row. Rollback is idempotent too.
// ─────────────────────────────────────────────────────────────────────────────
const fs = require('fs')
const path = require('path')
const crypto = require('crypto')
const mongoose = require('mongoose')

// ── args ─────────────────────────────────────────────────────────────────────
const argv = process.argv.slice(2)
const flag = (n) => argv.includes(n)
const opt = (n, d) => { const i = argv.indexOf(n); return i >= 0 && argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[i + 1] : d }
const APPLY = flag('--apply')
const ROLLBACK = opt('--rollback', null)
if (flag('--rollback') && !ROLLBACK) die('--rollback needs the path of a log file')
if (APPLY && ROLLBACK) die('Use either --apply or --rollback, not both')
const UPLOADS_DIR = path.resolve(opt('--uploads-dir', path.join(process.cwd(), 'public', 'uploads')))
const PRIVATE_DIR = path.resolve(opt('--private-dir', path.join(process.cwd(), 'data', 'private-uploads')))
const LIMIT = Math.max(0, Math.floor(Number(opt('--limit', '0')) || 0))
const ENV_FILE = path.resolve(opt('--env', path.join(process.cwd(), '.env.local')))
const ONLY = String(opt('--only', '') || '').split(',').map(x => x.trim()).filter(Boolean)
if (ONLY.some(x => !/^[a-f0-9]{24}$/i.test(x))) die('--only takes comma-separated 24-hex ids')

function die(msg) { console.error(msg); process.exit(1) }

function loadUri() {
  if (process.env.MONGODB_URI) return process.env.MONGODB_URI
  try {
    for (const line of fs.readFileSync(ENV_FILE, 'utf8').split(/\r?\n/)) {
      const m = line.match(/^\s*MONGODB_URI\s*=\s*(.*)\s*$/)
      if (m) return m[1].replace(/^['"]|['"]$/g, '')
    }
  } catch { /* fall through */ }
  die(`MONGODB_URI not set and not found in ${ENV_FILE}`)
}

// ── names / types ────────────────────────────────────────────────────────────
// Same shapes as lib/private-files.ts.
const FILE_NAME_RE = /^\d{10,16}-[a-f0-9]{12}\.(jpg|png|webp|gif|pdf)$/
const PUBLIC_URL_RE = /^(?:https?:\/\/[^/]+)?\/uploads\/([^/?#]+)$/
const PRIVATE_PREFIX = '/api/files/'
const MIME = { jpg: 'image/jpeg', png: 'image/png', webp: 'image/webp', gif: 'image/gif', pdf: 'application/pdf' }

/** The old public file name in a stored URL, or null when it is not one. */
function publicName(u) {
  if (typeof u !== 'string') return null
  const m = u.trim().match(PUBLIC_URL_RE)
  if (!m) return null
  const name = decodeURIComponent(m[1])
  if (!name || name.includes('/') || name.includes('\\') || name.includes('..')) return null
  return name
}

/** Type from the file's own bytes (never its name), as the upload route does. */
function sniff(file) {
  const fd = fs.openSync(file, 'r')
  const b = Buffer.alloc(12)
  try { fs.readSync(fd, b, 0, 12, 0) } finally { fs.closeSync(fd) }
  if (b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return 'jpg'
  if (b.slice(0, 4).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47]))) return 'png'
  if (b.slice(0, 3).toString('ascii') === 'GIF') return 'gif'
  if (b.slice(0, 4).toString('ascii') === 'RIFF' && b.slice(8, 12).toString('ascii') === 'WEBP') return 'webp'
  if (b.slice(0, 4).toString('ascii') === '%PDF') return 'pdf'
  return null
}

const newName = (ext) => `${Date.now()}-${crypto.randomBytes(6).toString('hex')}.${ext}`
const exists = (p) => { try { fs.accessSync(p); return true } catch { return false } }

/** Move a file, across filesystems too (copy, verify size, unlink). */
function moveFile(from, to) {
  try { fs.renameSync(from, to); return } catch (e) { if (e.code !== 'EXDEV') throw e }
  fs.copyFileSync(from, to, fs.constants.COPYFILE_EXCL)
  if (fs.statSync(from).size !== fs.statSync(to).size) throw new Error(`copy size mismatch ${from} -> ${to}`)
  fs.unlinkSync(from)
}

// ── log ──────────────────────────────────────────────────────────────────────
function writeJsonAtomic(file, obj) {
  const tmp = `${file}.tmp`
  fs.writeFileSync(tmp, JSON.stringify(obj, null, 2))
  fs.renameSync(tmp, file)
}

// ── scan ─────────────────────────────────────────────────────────────────────
// refs: one per stored reference { coll, id, path, from }; grouped by old file.
async function scan(db) {
  const refs = []
  const add = (coll, id, p, value, ownerType, ownerId, purpose) => {
    const name = publicName(value)
    if (name) refs.push({ coll, id, path: p, from: value, name, ownerType, ownerId: String(ownerId || ''), purpose })
  }
  const counts = { driverDocuments: 0, driverFace: 0, faceVerifications: 0, userIdPhotos: 0 }
  const ids = ONLY.map(x => new mongoose.Types.ObjectId(x))
  const byId = ids.length ? { _id: { $in: ids } } : {}
  const drivers = db.collection('drivers').find(
    { ...byId, $or: [{ 'documents.fileUrl': /\/uploads\// }, { 'documents.frontUrl': /\/uploads\// }, { 'documents.backUrl': /\/uploads\// }, { faceReferencePhotoUrl: /\/uploads\// }] },
    { projection: { documents: 1, faceReferencePhotoUrl: 1 } },
  )
  for await (const d of drivers) {
    ;(d.documents || []).forEach((doc, i) => {
      for (const f of ['fileUrl', 'frontUrl', 'backUrl']) {
        const before = refs.length
        add('drivers', d._id, `documents.${i}.${f}`, doc && doc[f], 'driver', d._id, 'kyc')
        if (refs.length > before) counts.driverDocuments++
      }
    })
    const before = refs.length
    add('drivers', d._id, 'faceReferencePhotoUrl', d.faceReferencePhotoUrl, 'driver', d._id, 'face')
    if (refs.length > before) counts.driverFace++
  }
  for await (const f of db.collection('faceverifications').find({ ...(ids.length ? { driverId: { $in: ids } } : {}), photoUrl: /\/uploads\// }, { projection: { photoUrl: 1, driverId: 1 } })) {
    const before = refs.length
    add('faceverifications', f._id, 'photoUrl', f.photoUrl, 'driver', f.driverId, 'face')
    if (refs.length > before) counts.faceVerifications++
  }
  for await (const u of db.collection('users').find({ ...byId, idPhotoUrl: /\/uploads\// }, { projection: { idPhotoUrl: 1 } })) {
    const before = refs.length
    add('users', u._id, 'idPhotoUrl', u.idPhotoUrl, 'rider', u._id, 'kyc')
    if (refs.length > before) counts.userIdPhotos++
  }
  const byFile = new Map()
  for (const r of refs) {
    if (!byFile.has(r.name)) byFile.set(r.name, [])
    byFile.get(r.name).push(r)
  }
  return { refs, counts, byFile }
}

// ── apply ────────────────────────────────────────────────────────────────────
async function apply(db, plan, logFile) {
  const uploads = db.collection('uploads')
  const log = {
    kind: 'kyc-private-migration', startedAt: new Date().toISOString(), finishedAt: null,
    uploadsDir: UPLOADS_DIR, privateDir: PRIVATE_DIR, entries: [],
  }
  writeJsonAtomic(logFile, log)
  fs.mkdirSync(PRIVATE_DIR, { recursive: true })
  const stats = { files: 0, refsRewritten: 0, missing: 0, unknownType: 0, resumed: 0, skippedLimit: 0 }

  for (const [oldName, refs] of plan.byFile) {
    if (LIMIT && stats.files >= LIMIT) { stats.skippedLimit++; continue }
    const oldPath = path.join(UPLOADS_DIR, oldName)
    // A run that crashed (or a re-run) left an Upload row naming this file.
    let row = await uploads.findOne({ migratedFrom: oldName })
    if (row) stats.resumed++
    if (!row) {
      if (!exists(oldPath)) { stats.missing++; console.warn(`  missing on disk, left as is: ${oldName} (${refs.length} reference(s))`); continue }
      const ext = sniff(oldPath)
      if (!ext) { stats.unknownType++; console.warn(`  not an image/PDF, left as is: ${oldName}`); continue }
      const owner = refs.find(r => r.ownerId) || refs[0]
      const st = fs.statSync(oldPath)
      row = {
        name: newName(ext), ownerType: owner.ownerType, ownerId: owner.ownerId, private: true,
        purpose: owner.purpose, mime: MIME[ext], size: st.size,
        // The file's own age, so the owner's daily upload quota is not charged.
        createdAt: st.mtime, migratedFrom: oldName, migratedAt: new Date(),
      }
      await uploads.insertOne(row)
    }
    const newPath = path.join(PRIVATE_DIR, row.name)
    const newUrl = PRIVATE_PREFIX + row.name
    const entry = { oldName, newName: row.name, newUrl, ownerType: row.ownerType, ownerId: row.ownerId, refs: [] }
    log.entries.push(entry)
    writeJsonAtomic(logFile, log)

    // Move: old → new. Both present = an interrupted copy; neither = gone.
    const hasOld = exists(oldPath), hasNew = exists(newPath)
    if (hasOld && !hasNew) moveFile(oldPath, newPath)
    else if (hasOld && hasNew) {
      if (fs.statSync(oldPath).size === fs.statSync(newPath).size) fs.unlinkSync(oldPath)
      else { fs.unlinkSync(newPath); moveFile(oldPath, newPath) }
    } else if (!hasOld && !hasNew) {
      stats.missing++
      console.warn(`  file gone from both places, references left as is: ${oldName}`)
      continue
    }

    // Rewrite each reference, only where it still holds the old value.
    for (const r of refs) {
      const res = await db.collection(r.coll).updateOne({ _id: r.id, [r.path]: r.from }, { $set: { [r.path]: newUrl } })
      if (res.modifiedCount) {
        stats.refsRewritten++
        entry.refs.push({ coll: r.coll, id: String(r.id), path: r.path, from: r.from, to: newUrl })
      }
    }
    entry.done = true
    writeJsonAtomic(logFile, log)
    stats.files++
  }
  log.finishedAt = new Date().toISOString()
  log.stats = stats
  writeJsonAtomic(logFile, log)
  return stats
}

// ── rollback ─────────────────────────────────────────────────────────────────
async function rollback(db, logFile) {
  let log
  try { log = JSON.parse(fs.readFileSync(logFile, 'utf8')) } catch (e) { die(`Cannot read log ${logFile}: ${e.message}`) }
  if (log.kind !== 'kyc-private-migration') die('Not a KYC migration log')
  const upDir = path.resolve(opt('--uploads-dir', log.uploadsDir))
  const prDir = path.resolve(opt('--private-dir', log.privateDir))
  const stats = { files: 0, refsRestored: 0, filesMovedBack: 0, rowsRemoved: 0 }
  for (const e of [...(log.entries || [])].reverse()) {
    for (const r of e.refs || []) {
      const res = await db.collection(r.coll).updateOne(
        { _id: new mongoose.Types.ObjectId(r.id), [r.path]: r.to }, { $set: { [r.path]: r.from } })
      if (res.modifiedCount) stats.refsRestored++
    }
    // Only move the file back when nothing points at its private URL any more.
    const stillUsed = await refsTo(db, e.newUrl)
    if (stillUsed) { console.warn(`  ${e.newUrl} is still referenced (${stillUsed}); file and Upload row kept`); continue }
    const from = path.join(prDir, e.newName), to = path.join(upDir, e.oldName)
    if (exists(from) && !exists(to)) { moveFile(from, to); stats.filesMovedBack++ }
    const del = await db.collection('uploads').deleteOne({ name: e.newName, migratedFrom: e.oldName })
    stats.rowsRemoved += del.deletedCount
    stats.files++
  }
  return stats
}

async function refsTo(db, url) {
  const n = (await db.collection('drivers').countDocuments({ $or: [{ 'documents.fileUrl': url }, { 'documents.frontUrl': url }, { 'documents.backUrl': url }, { faceReferencePhotoUrl: url }] }))
    + (await db.collection('faceverifications').countDocuments({ photoUrl: url }))
    + (await db.collection('users').countDocuments({ idPhotoUrl: url }))
  return n
}

// ── main ─────────────────────────────────────────────────────────────────────
async function main() {
  const uri = loadUri()
  await mongoose.connect(uri)
  const db = mongoose.connection.db
  const dbName = db.databaseName
  try {
    if (ROLLBACK) {
      console.log(`ROLLBACK of ${ROLLBACK} on database "${dbName}"`)
      const s = await rollback(db, path.resolve(ROLLBACK))
      console.log('Done:', JSON.stringify(s))
      return
    }
    const plan = await scan(db)
    console.log(`${APPLY ? 'APPLY' : 'DRY RUN'} on database "${dbName}"`)
    console.log(`  uploads dir : ${UPLOADS_DIR}`)
    console.log(`  private dir : ${PRIVATE_DIR}`)
    console.log(`  references still on /uploads: ${plan.refs.length}`, JSON.stringify(plan.counts))
    let missing = 0
    for (const name of plan.byFile.keys()) if (!exists(path.join(UPLOADS_DIR, name))) missing++
    console.log(`  distinct files: ${plan.byFile.size} (${missing} not found in the uploads dir)`)
    const sample = [...plan.byFile.entries()].slice(0, 5)
    for (const [name, refs] of sample) {
      console.log(`    ${name}  →  /api/files/<new random name>   [${refs.map(r => `${r.coll}:${r.id}.${r.path}`).join(', ')}]`)
    }
    if (!APPLY) {
      console.log('Nothing changed. Re-run with --apply to migrate.')
      return
    }
    if (plan.byFile.size === 0) { console.log('Nothing to migrate.'); return }
    const logFile = path.resolve(opt('--log', path.join(path.dirname(PRIVATE_DIR), `kyc-migration-${new Date().toISOString().replace(/[:.]/g, '-')}.json`)))
    console.log(`  log: ${logFile}`)
    const s = await apply(db, plan, logFile)
    console.log('Done:', JSON.stringify(s))
    console.log(`Rollback: node scripts/migrate-private-kyc.js --rollback "${logFile}"`)
  } finally {
    await mongoose.disconnect()
  }
}

main().catch(e => { console.error(e); process.exit(1) })
