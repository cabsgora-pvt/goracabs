#!/usr/bin/env node
// ─────────────────────────────────────────────────────────────────────────────
// Verification for two dispatch rules (not deployed logic — a test harness):
//
//   1. Busy drivers are never offered / shown a request
//      (lib/dispatch.ts → BUSY, busyRideFilter, busyDriverIds, driverIsBusy, candidatesFor)
//   2. A ride nobody took closes itself as "No driver found", refunding anything
//      captured at booking (lib/dispatch.ts → expireIfNoDriver,
//      expireUnmatchedRides; lib/refunds.ts settleCancelRefunds; lib/prepay.ts)
//   3. Rider/admin cancel of a prepaid ride refunds it (lib/refunds.ts → cancelRide)
//
// Runs the REAL TypeScript modules (compiled to a temp dir with the project's
// tsc) against a THROWAWAY MongoDB. It refuses any URI that is not localhost,
// and drops only its own database, so it can never touch dev or production data.
//
//   TEST_MONGODB_URI=mongodb://127.0.0.1:27999/gora_dispatch_test node scripts/verify-dispatch.js
// ─────────────────────────────────────────────────────────────────────────────
const path = require('path')
const fs = require('fs')
const os = require('os')
const { execFileSync } = require('child_process')
const Module = require('module')

const URI = process.env.TEST_MONGODB_URI
if (!URI || !/^mongodb:\/\/(127\.0\.0\.1|localhost)(:\d+)?\/[\w-]*test[\w-]*$/.test(URI)) {
  console.error('Set TEST_MONGODB_URI to a localhost database whose name contains "test".')
  process.exit(2)
}
process.env.MONGODB_URI = URI

const root = path.join(__dirname, '..')
const out = fs.mkdtempSync(path.join(os.tmpdir(), 'gora-dispatch-'))
// Compile with the project's own config (paths, strictness), emitting CommonJS.
const tsconfig = path.join(out, 'tsconfig.json')
fs.writeFileSync(tsconfig, JSON.stringify({
  extends: path.join(root, 'tsconfig.json'),
  compilerOptions: {
    noEmit: false, incremental: false, outDir: out, rootDir: root,
    module: 'commonjs', moduleResolution: 'node', target: 'es2020', plugins: [],
    typeRoots: [path.join(root, 'node_modules', '@types')], types: ['node'],
  },
  files: [path.join(root, 'lib', 'dispatch.ts'), path.join(root, 'lib', 'prepay.ts')],
  include: [],
}))
execFileSync(process.execPath, [path.join(root, 'node_modules', 'typescript', 'bin', 'tsc'), '-p', tsconfig],
  { stdio: 'inherit', cwd: root })

// '@/x' → compiled x
const origResolve = Module._resolveFilename
Module._resolveFilename = function (req, ...rest) {
  if (req.startsWith('@/')) req = path.join(out, req.slice(2))
  return origResolve.call(this, req, ...rest)
}
// Compiled files resolve 'mongoose' from the temp dir: point them at ours.
process.env.NODE_PATH = path.join(root, 'node_modules')
Module._initPaths()

const mongoose = require('mongoose')
const dispatch = require(path.join(out, 'lib', 'dispatch.js'))
const prepay = require(path.join(out, 'lib', 'prepay.js'))
const refunds = require(path.join(out, 'lib', 'refunds.js'))
const ServiceConfig = require(path.join(out, 'models', 'ServiceConfig.js')).default
const Ride = require(path.join(out, 'models', 'Ride.js')).default
const Driver = require(path.join(out, 'models', 'Driver.js')).default
const User = require(path.join(out, 'models', 'User.js')).default
const WalletTransaction = require(path.join(out, 'models', 'WalletTransaction.js')).default

let failed = 0, passed = 0
function check(name, cond, detail) {
  if (cond) { passed++; console.log('  ok   ' + name) }
  else { failed++; console.log('  FAIL ' + name + (detail !== undefined ? '  → ' + JSON.stringify(detail) : '')) }
}
const ago = (sec) => new Date(Date.now() - sec * 1000)
const ahead = (sec) => new Date(Date.now() + sec * 1000)
const P = { lat: 22.3039, lng: 70.8022 }   // pickup

async function makeRide(extra = {}, createdSecAgo = 0) {
  const r = await Ride.create({
    riderId: extra.riderId || new mongoose.Types.ObjectId(), service: 'taxi', vehicleType: 'Bike',
    pickupLat: P.lat, pickupLng: P.lng, dropLat: 22.31, dropLng: 70.81,
    fare: 500, totalFare: 500, status: 'pending', ...extra,
  })
  if (createdSecAgo) await Ride.collection.updateOne({ _id: r._id }, { $set: { createdAt: ago(createdSecAgo) } })
  return Ride.findById(r._id).lean()
}

async function main() {
  await mongoose.connect(URI)
  await mongoose.connection.db.dropDatabase()

  console.log('\n# 2. No driver found → ride closes itself')
  const T = dispatch.NO_DRIVER.TIMEOUT_SEC
  check('timeout is 3 minutes', T === 180)

  const fresh = await makeRide({}, T - 30)
  check('pending under 3 min is left alone', (await dispatch.expireIfNoDriver(fresh._id)) === false)
  check('…and is still pending', (await Ride.findById(fresh._id).lean()).status === 'pending')

  const old = await makeRide({ offeredTo: new mongoose.Types.ObjectId(), offerExpiresAt: ahead(10) }, T + 5)
  check('pending over 3 min is closed', (await dispatch.expireIfNoDriver(old._id)) === true)
  const o = await Ride.findById(old._id).lean()
  check('status cancelled / cancelledBy system / reason / fee 0',
    o.status === 'cancelled' && o.cancelledBy === 'system' && o.cancellationReason === 'No driver found' && o.cancellationFee === 0, o)
  check('offer cleared', o.offeredTo === null && o.offerExpiresAt === undefined, { offeredTo: o.offeredTo, exp: o.offerExpiresAt })
  check('refund bookkeeping settled (nothing captured)', o.refundPending === false && o.refundedAmount === 0, o)
  check('second call is a no-op (idempotent)', (await dispatch.expireIfNoDriver(old._id)) === false)

  const race = await makeRide({}, T + 60)
  const results = await Promise.all(Array.from({ length: 8 }, () => dispatch.expireIfNoDriver(race._id)))
  check('8 concurrent callers → exactly one closes it', results.filter(Boolean).length === 1, results)

  const acc = await makeRide({ status: 'accepted', driverId: new mongoose.Types.ObjectId() }, T + 600)
  check('an accepted ride is never touched', (await dispatch.expireIfNoDriver(acc._id)) === false
    && (await Ride.findById(acc._id).lean()).status === 'accepted')

  const schedFuture = await makeRide({ scheduledAt: ahead(3600) }, T + 600)
  check('future scheduledAt → untouched', (await dispatch.expireIfNoDriver(schedFuture._id)) === false)
  const schedSoon = await makeRide({ scheduledAt: ago(T - 20) }, T + 600)
  check('scheduledAt passed < 3 min ago → untouched', (await dispatch.expireIfNoDriver(schedSoon._id)) === false)
  const schedDue = await makeRide({ scheduledAt: ago(T + 5) }, T + 600)
  check('scheduledAt passed > 3 min ago → closed', (await dispatch.expireIfNoDriver(schedDue._id)) === true)
  const osFuture = await makeRide({ service: 'outstation', departureAt: ahead(86400) }, T + 600)
  check('outstation departing tomorrow → untouched', (await dispatch.expireIfNoDriver(osFuture._id)) === false)
  const hireFuture = await makeRide({ service: 'hire_driver', hireStartAt: ahead(7200) }, T + 600)
  check('hire starting later → untouched', (await dispatch.expireIfNoDriver(hireFuture._id)) === false)
  const unlinked = await makeRide({ service: 'outstation', paymentMode: 'online', prepaidUnlinked: true }, T + 600)
  check('prepaid but unlinked → never auto-closed', (await dispatch.expireIfNoDriver(unlinked._id)) === false)

  // Sweep path (driver feed): closes every overdue one, leaves the rest.
  const s1 = await makeRide({}, T + 30)
  const s2 = await makeRide({ service: 'delivery' }, T + 900)
  const s3 = await makeRide({}, 20)
  await dispatch.sweepExpiredOffers()
  const [a1, a2, a3] = await Promise.all([s1, s2, s3].map(r => Ride.findById(r._id).lean()))
  check('sweepExpiredOffers closes overdue rides', a1.status === 'cancelled' && a2.status === 'cancelled')
  check('sweepExpiredOffers leaves a fresh one', a3.status === 'pending')
  check('sweep left future-scheduled / unlinked alone',
    (await Ride.countDocuments({ _id: { $in: [schedFuture._id, osFuture._id, hireFuture._id, unlinked._id] }, status: 'pending' })) === 4)

  console.log('\n# Money: wallet prepay (outstation) is linked at booking and refunded')
  const rider = await User.create({ phone: '9990000001', name: 'R', walletBalance: 1000 })
  // What /wallet/pay writes before an outstation booking: a debit with ref ''.
  rider.walletBalance -= 450; await rider.save()
  const debit = await WalletTransaction.create({ userId: rider._id, type: 'debit', amount: 450, balanceAfter: 550, note: 'Ride payment', source: 'ride', ref: '' })
  const osRide = await Ride.create({
    riderId: rider._id, service: 'outstation', vehicleType: 'Sedan', fare: 500, totalFare: 500,
    paymentMode: 'wallet', status: 'pending', prepaidUnlinked: prepay.chargedAtBooking('outstation', 'wallet'),
  })
  await prepay.linkPrepayment(osRide, String(rider._id), {})
  let osr = await Ride.findById(osRide._id).lean()
  check('wallet debit linked: prepaidAmount 450, via wallet, not unlinked',
    osr.prepaidAmount === 450 && osr.prepaidVia === 'wallet' && osr.prepaidRef === String(debit._id) && osr.prepaidUnlinked === false, osr)
  check('debit row now points at the ride', (await WalletTransaction.findById(debit._id).lean()).ref === String(osRide._id))

  const osRide2 = await Ride.create({ riderId: rider._id, service: 'outstation', vehicleType: 'Sedan', fare: 500, totalFare: 500,
    paymentMode: 'wallet', status: 'pending', prepaidUnlinked: true })
  await prepay.linkPrepayment(osRide2, String(rider._id), {})
  check('the same debit cannot back a second ride', (await Ride.findById(osRide2._id).lean()).prepaidUnlinked === true)

  const stranger = await User.create({ phone: '9990000002', name: 'S', walletBalance: 0 })
  await WalletTransaction.create({ userId: stranger._id, type: 'debit', amount: 300, balanceAfter: 0, source: 'ride', ref: '' })
  const osRide3 = await Ride.create({ riderId: rider._id, service: 'outstation', vehicleType: 'Sedan', fare: 500, totalFare: 500,
    paymentMode: 'wallet', status: 'pending', prepaidUnlinked: true })
  await prepay.linkPrepayment(osRide3, String(rider._id), {})
  check("another user's debit is never linked", (await Ride.findById(osRide3._id).lean()).prepaidUnlinked === true)

  const osOnline = await Ride.create({ riderId: rider._id, service: 'outstation', vehicleType: 'Sedan', fare: 500, totalFare: 500,
    paymentMode: 'online', status: 'pending', prepaidUnlinked: true })
  await prepay.linkPrepayment(osOnline, String(rider._id), { prepaid: { orderId: 'order_x', paymentId: 'pay_x', signature: 'bad' } })
  check('online prepay with no verifiable Razorpay proof stays unlinked', (await Ride.findById(osOnline._id).lean()).prepaidUnlinked === true)

  const cashTaxi = await Ride.create({ riderId: rider._id, service: 'taxi', vehicleType: 'Bike', fare: 100, paymentMode: 'wallet', status: 'pending' })
  await prepay.linkPrepayment(cashTaxi, String(rider._id), {})
  check('taxi (paid after the trip) is not treated as prepaid', (await Ride.findById(cashTaxi._id).lean()).prepaidUnlinked === false)

  await Ride.collection.updateOne({ _id: osRide._id }, { $set: { createdAt: ago(T + 10) } })
  check('linked prepaid outstation IS auto-closed', (await dispatch.expireIfNoDriver(osRide._id)) === true)
  osr = await Ride.findById(osRide._id).lean()
  const r1 = await User.findById(rider._id).lean()
  check('rider wallet credited back 450 (550 → 1000)', r1.walletBalance === 1000, r1.walletBalance)
  const rows = await WalletTransaction.find({ userId: rider._id, source: 'refund' }).lean()
  check('one refund row: credit 450, balanceAfter 1000, idempotency ref',
    rows.length === 1 && rows[0].type === 'credit' && rows[0].amount === 450 && rows[0].balanceAfter === 1000
      && rows[0].ref === `refund:${osRide._id}:prepaid`, rows)
  check('ride records refundedAmount 450, refundPending false', osr.refundedAmount === 450 && osr.refundPending === false, osr)

  // Retry after a "crash": force the flag back on; the ledger ref stops a double pay.
  await Ride.updateOne({ _id: osRide._id }, { $set: { refundPending: true }, $unset: { refundLeaseAt: 1 } })
  await dispatch.expireUnmatchedRides()
  check('a retried refund never pays twice', (await User.findById(rider._id).lean()).walletBalance === 1000
    && (await WalletTransaction.countDocuments({ userId: rider._id, source: 'refund' })) === 1)

  // Concurrency on settlement: lease lets one runner through.
  const racer = await User.create({ phone: '9990000003', name: 'Q', walletBalance: 0 })
  const rr = await Ride.create({ riderId: racer._id, service: 'outstation', vehicleType: 'Sedan', fare: 500, totalFare: 500,
    paymentMode: 'wallet', status: 'cancelled', cancelledBy: 'system', refundPending: true, prepaidAmount: 200, prepaidVia: 'wallet' })
  await Promise.all(Array.from({ length: 6 }, () => refunds.settleCancelRefunds(rr._id)))
  check('6 concurrent settlements credit exactly once', (await User.findById(racer._id).lean()).walletBalance === 200)

  console.log('\n# Money: a paid split share is returned to its payer')
  const friend = await User.create({ phone: '9990000004', name: 'F', walletBalance: 0 })
  const sp = await makeRide({ splitRequests: [
    { phone: '9990000004', name: 'F', share: 249.5, status: 'paid', paidBy: friend._id, paidAt: new Date() },
    { phone: '9990000005', name: 'G', share: 249.5, status: 'pending' },
  ], splitCollected: 250 }, T + 10)
  await dispatch.expireIfNoDriver(sp._id)
  check('split payer credited their rounded share (250)', (await User.findById(friend._id).lean()).walletBalance === 250)
  check('unpaid split request refunds nothing', (await WalletTransaction.countDocuments({ source: 'refund', ref: new RegExp(String(sp._id)) })) === 1)

  console.log('\n# 1. Busy drivers are not offered or shown requests')
  check('accepted rides count as busy within 60 min of being due', dispatch.BUSY.ACCEPTED_DUE_WITHIN_MIN === 60)
  const near = (d) => ({ lat: P.lat + d, lng: P.lng + d })
  const base = { status: 'approved', isOnline: true, selectedVehicleTypeName: 'Bike', locationUpdatedAt: new Date() }
  let phoneN = 8880000100
  const mkDriver = (name, d) => Driver.create({ ...base, phone: String(phoneN++), name, currentLat: near(d).lat, currentLng: near(d).lng })
  const busyFor = async (rideExtra) => {
    const d = await mkDriver('t', 1)   // far away: only the busy rule is under test here
    const r = await Ride.create({ service: 'taxi', vehicleType: 'Bike', driverId: d._id, ...rideExtra })
    return { busy: await dispatch.driverIsBusy(String(d._id)), exceptSelf: await dispatch.driverIsBusy(String(d._id), String(r._id)) }
  }
  let b
  b = await busyFor({ status: 'ongoing' });  check('ongoing → busy', b.busy === true)
  b = await busyFor({ status: 'arrived' });  check('arrived → busy', b.busy === true)
  b = await busyFor({ status: 'accepted' }); check('accepted instant ride → busy', b.busy === true)
  check('…but not counting the ride being accepted itself', b.exceptSelf === false)
  b = await busyFor({ status: 'accepted', service: 'outstation', departureAt: ahead(86400) })
  check('accepted outstation due tomorrow → NOT busy', b.busy === false)
  b = await busyFor({ status: 'accepted', service: 'outstation', departureAt: ahead(30 * 60) })
  check('accepted outstation due in 30 min → busy', b.busy === true)
  b = await busyFor({ status: 'accepted', scheduledAt: ahead(3 * 3600) })
  check('accepted scheduled taxi due in 3 h → NOT busy', b.busy === false)
  b = await busyFor({ status: 'accepted', scheduledAt: ago(600) })
  check('accepted scheduled ride already due → busy', b.busy === true)
  b = await busyFor({ status: 'accepted', service: 'hire_driver', hireStartAt: ahead(45 * 60) })
  check('accepted hire starting in 45 min → busy', b.busy === true)
  b = await busyFor({ status: 'accepted', service: 'hire_driver', hireStartAt: ahead(61 * 60) })
  check('accepted hire starting in 61 min → NOT busy', b.busy === false)
  b = await busyFor({ status: 'accepted', service: 'rental', scheduledAt: ahead(30 * 60), departureAt: ahead(2 * 86400) })
  check('the latest due field counts (departure in 2 days) → NOT busy', b.busy === false)
  b = await busyFor({ status: 'completed' }); check('completed → not busy', b.busy === false)
  b = await busyFor({ status: 'cancelled' }); check('cancelled → not busy', b.busy === false)

  // Ranking: who actually gets the offer.
  const freeD = await mkDriver('Free', 0.01)
  const tmrD = await mkDriver('AcceptedForTomorrow', 0.003)
  await Ride.create({ service: 'outstation', vehicleType: 'Bike', status: 'accepted', driverId: tmrD._id, departureAt: ahead(86400) })
  const soonD = await mkDriver('AcceptedDueIn30', 0.002)
  await Ride.create({ service: 'outstation', vehicleType: 'Bike', status: 'accepted', driverId: soonD._id, departureAt: ahead(1800) })
  // Nearest, on an ongoing trip ending ~200 m away: the "chaining" case
  // rankCandidates' look-ahead would otherwise keep as a candidate.
  const busyD = await mkDriver('Busy', 0.001)
  await Ride.create({ service: 'taxi', vehicleType: 'Bike', status: 'ongoing', driverId: busyD._id,
    pickupLat: 22.2, pickupLng: 70.7, dropLat: near(0.002).lat, dropLng: near(0.002).lng })

  const ids = await dispatch.busyDriverIds([freeD, tmrD, soonD, busyD].map(d => String(d._id)))
  check('busyDriverIds = {ongoing, due-in-30}', ids.size === 2 && ids.has(String(busyD._id)) && ids.has(String(soonD._id)), [...ids])
  const want = await makeRide({}, 0)
  const cands = await dispatch.candidatesFor(want)
  const cid = cands.map(c => c.id)
  check('candidatesFor excludes the ongoing (chainable) driver', !cid.includes(String(busyD._id)), cid)
  check('candidatesFor excludes the driver whose accepted trip is due in 30 min', !cid.includes(String(soonD._id)), cid)
  check('candidatesFor keeps the driver whose accepted trip is tomorrow', cid.includes(String(tmrD._id)), cid)
  check('candidatesFor keeps the free driver', cid.includes(String(freeD._id)), cid)
  const offered = await dispatch.offerNext(String(want._id))
  check('offerNext offers the nearest non-busy driver (accepted-for-tomorrow)', offered === String(tmrD._id), offered)

  console.log('\n# 3. Rider/admin cancel of a prepaid outstation ride')
  await ServiceConfig.create({ service: 'outstation', cancellationFee: 100 })
  let uN = 9990001000
  const mkUser = (balance = 0) => User.create({ phone: String(uN++), name: 'U', walletBalance: balance })
  const bal = async (u) => (await User.findById(u._id).lean()).walletBalance
  const refundRows = (ride) => WalletTransaction.find({ source: 'refund', ref: new RegExp('^refund:' + ride._id + ':') }).lean()
  const prepaidRide = (rider, status, amount, extra = {}) => Ride.create({
    riderId: rider._id, service: 'outstation', vehicleType: 'Sedan', fare: 500, totalFare: 500, paymentMode: 'wallet',
    status, prepaidAmount: amount, prepaidVia: amount ? 'wallet' : undefined, prepaidUnlinked: false, ...extra,
  })

  // A. pending: full refund, plus paid split shares back to their payers
  {
    const u = await mkUser(), f = await mkUser()
    const r = await prepaidRide(u, 'pending', 450, { splitRequests: [{ phone: '1', name: 'F', share: 150, status: 'paid', paidBy: f._id }] })
    const out = await refunds.cancelRide(r._id, 'rider', 'Plan changed')
    const after = await Ride.findById(r._id).lean()
    check('A pending: fee 0, rider gets 450, split payer gets 150', out.cancellationFee === 0 && await bal(u) === 450 && await bal(f) === 150)
    check('A pending: refundedAmount 600, refundPending false, cancelledFromStatus pending',
      out.refundedAmount === 600 && after.refundedAmount === 600 && after.refundPending === false && after.cancelledFromStatus === 'pending', after)
  }
  // B. accepted, rider cancels: prepaid minus the fee; fee retained; split NOT refunded (driver already credited by split/pay)
  {
    const u = await mkUser(), f = await mkUser()
    const drv = await mkDriver('Assigned', 1)
    const r = await prepaidRide(u, 'accepted', 450, { driverId: drv._id,
      splitRequests: [{ phone: '1', name: 'F', share: 150, status: 'paid', paidBy: f._id }] })
    const out = await refunds.cancelRide(r._id, 'rider', 'Driver is too far')
    const after = await Ride.findById(r._id).lean()
    check('B accepted: fee 100, rider refunded 350', out.cancellationFee === 100 && await bal(u) === 350 && after.cancellationFee === 100)
    check('B accepted: refundedAmount 350 recorded', after.refundedAmount === 350, after.refundedAmount)
    check('B accepted: driver NOT credited the fee', ((await Driver.findById(drv._id).lean()).walletBalance || 0) === 0)
    check('B accepted: split share not refunded once a driver was assigned', await bal(f) === 0)
    const rows = await refundRows(r)
    check('B accepted: one refund row, note says the fee was kept', rows.length === 1 && rows[0].amount === 350 && /fee kept/.test(rows[0].note), rows)
  }
  // C. arrived with prepaid smaller than the fee: refund 0, never negative
  {
    const u = await mkUser()
    const r = await prepaidRide(u, 'arrived', 80, { driverId: new mongoose.Types.ObjectId() })
    const out = await refunds.cancelRide(r._id, 'rider')
    check('C fee > prepaid: refund 0, no row, balance untouched',
      out.refundedAmount === 0 && await bal(u) === 0 && (await refundRows(r)).length === 0)
  }
  // D. admin cancels after accept: no fee, full refund
  {
    const u = await mkUser()
    const r = await prepaidRide(u, 'accepted', 450, { driverId: new mongoose.Types.ObjectId() })
    const out = await refunds.cancelRide(r._id, 'admin', 'Support')
    check('D admin cancel after accept: fee 0, full 450 back', out.cancellationFee === 0 && await bal(u) === 450)
  }
  // E. prepaid but unlinked: flagged for admin, no automatic refund
  {
    const u = await mkUser()
    const r = await prepaidRide(u, 'pending', 0, { paymentMode: 'online', prepaidUnlinked: true })
    const out = await refunds.cancelRide(r._id, 'rider')
    const after = await Ride.findById(r._id).lean()
    check('E unlinked: refundReview prepay_unlinked, nothing refunded',
      out.review === 'prepay_unlinked' && after.refundReview === 'prepay_unlinked' && await bal(u) === 0 && (await refundRows(r)).length === 0, after)
    check('E unlinked: not left pending for the sweep', after.refundPending === false)
  }
  // F. cancelled mid-trip: flagged, no automatic refund
  {
    const u = await mkUser()
    const r = await prepaidRide(u, 'ongoing', 450, { driverId: new mongoose.Types.ObjectId() })
    const out = await refunds.cancelRide(r._id, 'admin')
    const after = await Ride.findById(r._id).lean()
    check('F ongoing: refundReview cancelled_mid_trip, nothing refunded',
      out.review === 'cancelled_mid_trip' && after.refundReview === 'cancelled_mid_trip' && await bal(u) === 0, after)
  }
  // G. cancelling twice: second is a no-op, paid once
  {
    const u = await mkUser()
    const r = await prepaidRide(u, 'pending', 450)
    await refunds.cancelRide(r._id, 'rider')
    const again = await refunds.cancelRide(r._id, 'rider')
    check('G double cancel: second reports alreadyCancelled, paid once',
      again.alreadyCancelled === true && await bal(u) === 450 && (await refundRows(r)).length === 1)
  }
  // H. six concurrent cancels: one transition, one refund
  {
    const u = await mkUser()
    const r = await prepaidRide(u, 'accepted', 450, { driverId: new mongoose.Types.ObjectId() })
    const outs = await Promise.all(Array.from({ length: 6 }, () => refunds.cancelRide(r._id, 'rider')))
    const won = outs.filter(o => o.ride)
    check('H concurrent cancels: exactly one cancels it', won.length === 1, outs.map(o => o.alreadyCancelled ? 'already' : o.error || 'won'))
    check('H concurrent cancels: refunded once (450 - 100 fee)', await bal(u) === 350 && (await refundRows(r)).length === 1)
  }
  // I. rider cancel racing the system's "No driver found" close
  {
    const u = await mkUser()
    const r = await prepaidRide(u, 'pending', 450)
    await Ride.collection.updateOne({ _id: r._id }, { $set: { createdAt: ago(T + 30) } })
    const [x, y] = await Promise.all([refunds.cancelRide(r._id, 'rider'), dispatch.expireIfNoDriver(r._id)])
    const winners = (x.ride ? 1 : 0) + (y ? 1 : 0)
    check('I rider cancel vs system close: exactly one wins', winners === 1, { rider: !!x.ride, system: y })
    check('I ...and the 450 comes back exactly once', await bal(u) === 450 && (await refundRows(r)).length === 1)
  }
  // J. a refund interrupted after the cancel is finished by the sweep, once
  {
    const u = await mkUser()
    const r = await prepaidRide(u, 'pending', 450)
    // The cancel's atomic update landed, then the process "died" before paying.
    await Ride.updateOne({ _id: r._id }, { $set: { status: 'cancelled', cancelledBy: 'rider', cancelledFromStatus: 'pending', cancellationFee: 0, refundPending: true } })
    await dispatch.expireUnmatchedRides()
    await Ride.updateOne({ _id: r._id }, { $set: { refundPending: true }, $unset: { refundLeaseAt: 1 } })
    await dispatch.expireUnmatchedRides()
    check('J interrupted refund: sweep pays it, and a retry does not pay twice', await bal(u) === 450 && (await refundRows(r)).length === 1)
  }
  // K. cash taxi cancel: nothing to refund, nothing flagged
  {
    const u = await mkUser()
    const r = await Ride.create({ riderId: u._id, service: 'taxi', vehicleType: 'Bike', fare: 100, paymentMode: 'cash', status: 'pending' })
    const out = await refunds.cancelRide(r._id, 'rider')
    const after = await Ride.findById(r._id).lean()
    check('K cash taxi: no refund, no review flag', out.refundedAmount === 0 && !after.refundReview && after.refundPending === false && await bal(u) === 0)
  }
  // L. a completed ride cannot be cancelled
  {
    const r = await Ride.create({ service: 'taxi', vehicleType: 'Bike', status: 'completed' })
    const out = await refunds.cancelRide(r._id, 'rider')
    check('L completed ride: 400, unchanged', out.status === 400 && (await Ride.findById(r._id).lean()).status === 'completed')
  }

  await mongoose.connection.db.dropDatabase()
  await mongoose.disconnect()
  fs.rmSync(out, { recursive: true, force: true })
  console.log(`\n${passed} passed, ${failed} failed`)
  process.exit(failed ? 1 : 0)
}

main().catch(async (e) => {
  console.error(e)
  try { await mongoose.disconnect() } catch {}
  process.exit(1)
})
