/**
 * Clear test data from MongoDB.
 *
 * Usage:
 *   node scripts/clear-data.js              # clear all data EXCEPT admin users
 *   node scripts/clear-data.js --all        # WIPE EVERYTHING including admin users
 *   node scripts/clear-data.js --only=users,rides   # clear specific collections only
 *
 * Production server:
 *   MONGODB_URI='mongodb://goraadmin:Gora%409424@127.0.0.1:27017/goraadmin?authSource=admin' \
 *     node scripts/clear-data.js
 */
const mongoose = require('mongoose')
const fs = require('fs')
const path = require('path')

// Try to load MONGODB_URI from env first, else from .env.production / .env.local
function loadUri() {
  if (process.env.MONGODB_URI) return process.env.MONGODB_URI
  for (const f of ['.env.production', '.env.local', '.env']) {
    const p = path.join(process.cwd(), f)
    if (!fs.existsSync(p)) continue
    const line = fs.readFileSync(p, 'utf8').split('\n').find(l => l.startsWith('MONGODB_URI='))
    if (line) return line.replace('MONGODB_URI=', '').trim()
  }
  return 'mongodb://localhost:27017/goraadmin'
}
const URI = loadUri()

// All collections we use
const ALL_COLLECTIONS = [
  'users', 'drivers',
  'rides', 'transactions', 'withdrawals',
  'vehicletypes', 'zones', 'surgeprices', 'serviceconfigs',
  'promocodes', 'banners',
  'supporttickets', 'faqs', 'soscontacts',
  'pushnotifications', 'fleetowners',
]

async function main() {
  const args = process.argv.slice(2)
  const wipeAll = args.includes('--all')
  const onlyArg = args.find(a => a.startsWith('--only='))
  const only = onlyArg ? onlyArg.split('=')[1].split(',').map(s => s.trim()) : null

  let toClear = only || ALL_COLLECTIONS
  if (wipeAll) toClear = [...toClear, 'admins', 'settings']

  console.log('Connecting to MongoDB...')
  await mongoose.connect(URI)
  console.log('Connected!\n')

  const db = mongoose.connection.db
  const existing = (await db.listCollections().toArray()).map(c => c.name)

  console.log(wipeAll ? '⚠️  WIPING EVERYTHING (including admins)' : '🧹 Clearing test data (admins preserved)')
  console.log('───────────────────────────────────────────')

  for (const name of toClear) {
    if (!existing.includes(name)) {
      console.log(`  • ${name.padEnd(20)} — skipped (no collection)`)
      continue
    }
    const result = await db.collection(name).deleteMany({})
    console.log(`  ✓ ${name.padEnd(20)} — ${result.deletedCount} removed`)
  }

  console.log('\n✅ Done.')
  if (!wipeAll) console.log('   Admin users + settings preserved.')
  console.log('   Re-seed demo data: node scripts/seed.js')
  await mongoose.disconnect()
}

main().catch(e => { console.error('Failed:', e.message); process.exit(1) })
