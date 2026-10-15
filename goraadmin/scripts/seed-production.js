#!/usr/bin/env node
// ─────────────────────────────────────────────────────────────────────────────
// Launch pricing for every service in the launch cities (Rajkot, Jodhpur).
//
//   node scripts/seed-production.js           # fill only what is missing
//   node scripts/seed-production.js --force   # also replace pricing/rental
//                                             # packages a zone already has
//
// Safe to re-run. It never deletes anything:
// - vehicle types are matched by name (services/capacity set; created if absent)
// - zones are matched by name; a zone's polygon is never touched if it exists
// - service configs (cancellation fees) and admin SOS contacts are only ever
//   inserted, so values edited later in the admin panel are kept.
//
// Every number here is a starting point to be tuned from the admin panel.
// Reads MONGODB_URI from .env.local, like scripts/speed-profile-cron.js.
// ─────────────────────────────────────────────────────────────────────────────
const path = require('path')
const fs = require('fs')
const mongoose = require('mongoose')

const FORCE = process.argv.includes('--force')

function loadEnvLocal() {
  const file = path.join(__dirname, '..', '.env.local')
  if (!fs.existsSync(file)) return
  for (const raw of fs.readFileSync(file, 'utf8').split('\n')) {
    const line = raw.trim()
    if (!line || line.startsWith('#')) continue
    const eq = line.indexOf('=')
    if (eq === -1) continue
    const key = line.slice(0, eq).trim()
    if (process.env[key] === undefined) process.env[key] = line.slice(eq + 1).trim()
  }
}

// ── Vehicles ────────────────────────────────────────────────────────────────
// `services` drives which vehicles show for outstation; the rest come from
// zone pricing rows. Keys match Ride.service / the admin vehicle-types page.
const VEHICLES = [
  { name: 'Bike', capacity: 1, sortOrder: 1, services: ['taxi', 'delivery'],
    baseFare: 20, perKm: 6, perMin: 0.5, minFare: 30 },
  { name: 'Auto', capacity: 3, sortOrder: 2, services: ['taxi', 'delivery', 'rental'],
    baseFare: 30, perKm: 11, perMin: 1, minFare: 45 },
  { name: 'Cab', capacity: 4, sortOrder: 3, services: ['taxi', 'rental', 'outstation', 'hire_driver'],
    baseFare: 50, perKm: 13, perMin: 1.5, minFare: 90 },
  { name: 'Prime Sedan', capacity: 4, sortOrder: 4, services: ['taxi', 'rental', 'outstation', 'hire_driver'],
    baseFare: 60, perKm: 15, perMin: 1.5, minFare: 110, image: '/uploads/vehicles/prime-sedan.png' },
  { name: 'Prime SUV', capacity: 6, sortOrder: 5, services: ['taxi', 'rental', 'outstation', 'hire_driver'],
    baseFare: 80, perKm: 18, perMin: 2, minFare: 150, image: '/uploads/vehicles/prime-suv.png' },
  { name: 'Mini Truck', capacity: 1, sortOrder: 6, services: ['delivery'],
    baseFare: 150, perKm: 20, perMin: 1.5, minFare: 250, image: '/uploads/vehicles/mini-truck.png' },
]

// ── Per-zone pricing ────────────────────────────────────────────────────────
// In-city fare = baseFare (covers first 2 km) + perKm × (km − 2)
//                + perMin × minutes (the estimator uses 3 min per km)
//                + perKg × kg (parcel only), floored at minFare.
const PRICING = [
  // Taxi
  { service: 'taxi', vehicle: 'Bike', baseFare: 20, perKm: 6, perMin: 0.5, minFare: 30 },
  { service: 'taxi', vehicle: 'Auto', baseFare: 30, perKm: 11, perMin: 1, minFare: 45 },
  { service: 'taxi', vehicle: 'Cab', baseFare: 50, perKm: 13, perMin: 1.5, minFare: 90 },
  { service: 'taxi', vehicle: 'Prime Sedan', baseFare: 60, perKm: 15, perMin: 1.5, minFare: 110 },
  { service: 'taxi', vehicle: 'Prime SUV', baseFare: 80, perKm: 18, perMin: 2, minFare: 150 },
  // Parcel (the app caps parcels at 20 kg)
  { service: 'delivery', vehicle: 'Bike', baseFare: 30, perKm: 7, perMin: 0.5, perKg: 2, minFare: 40 },
  { service: 'delivery', vehicle: 'Auto', baseFare: 60, perKm: 12, perMin: 1, perKg: 1, minFare: 80 },
  { service: 'delivery', vehicle: 'Mini Truck', baseFare: 150, perKm: 20, perMin: 1.5, perKg: 0, minFare: 250 },
  // Hire a driver (rider's own car, by its class): base + hours × perHour
  // (+ return charge one way)
  { service: 'hire_driver', vehicle: 'Cab', baseFare: 100, perHour: 120, hireReturnCharge: 100, minFare: 250 },
  { service: 'hire_driver', vehicle: 'Prime Sedan', baseFare: 100, perHour: 130, hireReturnCharge: 100, minFare: 280 },
  { service: 'hire_driver', vehicle: 'Prime SUV', baseFare: 120, perHour: 150, hireReturnCharge: 120, minFare: 320 },
  // Outstation: one way = base + km × perKm, plus emptyReturnPercent for the
  // driver's empty drive back; round trip uses the rt* rates. Driver
  // allowance is per day; night halt only on round trips with a 6h+ leg.
  { service: 'outstation', vehicle: 'Cab', baseFare: 300, perKm: 10, minFare: 1000,
    emptyReturnPercent: 25, rtBaseFare: 300, rtPerKm: 9, nightHaltCharge: 300,
    driverAllowance: 300, kmLimitPerDay: 300, extraKmRate: 10, gstPercent: 0 },
  { service: 'outstation', vehicle: 'Prime Sedan', baseFare: 300, perKm: 12, minFare: 1200,
    emptyReturnPercent: 25, rtBaseFare: 300, rtPerKm: 11, nightHaltCharge: 300,
    driverAllowance: 300, kmLimitPerDay: 300, extraKmRate: 12, gstPercent: 0 },
  { service: 'outstation', vehicle: 'Prime SUV', baseFare: 400, perKm: 15, minFare: 1500,
    emptyReturnPercent: 25, rtBaseFare: 400, rtPerKm: 14, nightHaltCharge: 350,
    driverAllowance: 350, kmLimitPerDay: 300, extraKmRate: 15, gstPercent: 0 },
]

const RENTAL_PACKAGES = [
  // Auto
  { vehicle: 'Auto', hours: 1, km: 10, basePrice: 149, extraHourRate: 100, extraKmRate: 10, nightCharge: 100 },
  { vehicle: 'Auto', hours: 2, km: 20, basePrice: 279, extraHourRate: 100, extraKmRate: 10, nightCharge: 100 },
  { vehicle: 'Auto', hours: 4, km: 40, basePrice: 499, extraHourRate: 100, extraKmRate: 10, nightCharge: 100 },
  // Cab
  { vehicle: 'Cab', hours: 1, km: 10, basePrice: 249, extraHourRate: 150, extraKmRate: 12, nightCharge: 200 },
  { vehicle: 'Cab', hours: 2, km: 20, basePrice: 449, extraHourRate: 150, extraKmRate: 12, nightCharge: 200 },
  { vehicle: 'Cab', hours: 4, km: 40, basePrice: 849, extraHourRate: 150, extraKmRate: 12, nightCharge: 200 },
  { vehicle: 'Cab', hours: 8, km: 80, basePrice: 1599, extraHourRate: 150, extraKmRate: 12, nightCharge: 200 },
  { vehicle: 'Cab', hours: 12, km: 120, basePrice: 2299, extraHourRate: 150, extraKmRate: 12, nightCharge: 200 },
  // Prime Sedan
  { vehicle: 'Prime Sedan', hours: 1, km: 10, basePrice: 299, extraHourRate: 180, extraKmRate: 14, nightCharge: 250 },
  { vehicle: 'Prime Sedan', hours: 2, km: 20, basePrice: 549, extraHourRate: 180, extraKmRate: 14, nightCharge: 250 },
  { vehicle: 'Prime Sedan', hours: 4, km: 40, basePrice: 999, extraHourRate: 180, extraKmRate: 14, nightCharge: 250 },
  { vehicle: 'Prime Sedan', hours: 8, km: 80, basePrice: 1899, extraHourRate: 180, extraKmRate: 14, nightCharge: 250 },
  { vehicle: 'Prime Sedan', hours: 12, km: 120, basePrice: 2699, extraHourRate: 180, extraKmRate: 14, nightCharge: 250 },
  // Prime SUV
  { vehicle: 'Prime SUV', hours: 1, km: 10, basePrice: 399, extraHourRate: 220, extraKmRate: 17, nightCharge: 300 },
  { vehicle: 'Prime SUV', hours: 2, km: 20, basePrice: 699, extraHourRate: 220, extraKmRate: 17, nightCharge: 300 },
  { vehicle: 'Prime SUV', hours: 4, km: 40, basePrice: 1299, extraHourRate: 220, extraKmRate: 17, nightCharge: 300 },
  { vehicle: 'Prime SUV', hours: 8, km: 80, basePrice: 2399, extraHourRate: 220, extraKmRate: 17, nightCharge: 300 },
  { vehicle: 'Prime SUV', hours: 12, km: 120, basePrice: 3399, extraHourRate: 220, extraKmRate: 17, nightCharge: 300 },
]

const COMMISSION_PERCENT = 20

// Only used when a zone does not exist yet — an existing zone keeps the
// polygon drawn for it in the admin panel.
const CITIES = [
  { name: 'Rajkot', lat: 22.3039, lng: 70.8022, radiusKm: 9 },
  { name: 'Jodhpur', lat: 26.2389, lng: 73.0243, radiusKm: 10 },
]

// Charged only when the rider cancels after a driver has accepted.
const CANCELLATION_FEES = { taxi: 20, delivery: 20, rental: 50, hire_driver: 50, outstation: 100 }

// National emergency numbers, shown in every user's and driver's SOS list.
const SOS_CONTACTS = [
  { name: 'Police', phone: '112', relation: 'Emergency' },
  { name: 'Ambulance', phone: '108', relation: 'Emergency' },
  { name: 'Women Helpline', phone: '1091', relation: 'Emergency' },
]

function octagon({ lat, lng, radiusKm }) {
  const dLat = radiusKm / 111
  const dLng = radiusKm / (111 * Math.cos((lat * Math.PI) / 180))
  return Array.from({ length: 8 }, (_, i) => {
    const a = (i * Math.PI) / 4
    return { lat: +(lat + dLat * Math.sin(a)).toFixed(6), lng: +(lng + dLng * Math.cos(a)).toFixed(6) }
  })
}

async function main() {
  loadEnvLocal()
  if (!process.env.MONGODB_URI) throw new Error('MONGODB_URI not set (expected in .env.local)')
  await mongoose.connect(process.env.MONGODB_URI)
  const db = mongoose.connection.db
  const now = new Date()

  // Vehicle types
  const vtByName = {}
  for (const v of VEHICLES) {
    const { name, image, ...fields } = v
    const onInsert = { imageUrl: image || '', baseDistance: 2, waitingCharge: 1, isAcceptShareRide: false, createdAt: now }
    const update = FORCE
      ? { $set: { ...fields, isActive: true, updatedAt: now }, $setOnInsert: onInsert }
      : { $setOnInsert: { ...fields, ...onInsert, isActive: true, updatedAt: now } }
    const res = await db.collection('vehicletypes').findOneAndUpdate(
      { name }, update, { upsert: true, returnDocument: 'after' },
    )
    let doc = res.value || res
    // Give an existing type the bundled image only if it has none, so a photo
    // uploaded from the admin panel is never replaced.
    if (image && !doc.imageUrl) {
      await db.collection('vehicletypes').updateOne({ _id: doc._id }, { $set: { imageUrl: image } })
      doc = { ...doc, imageUrl: image }
    }
    vtByName[name] = doc
    console.log(`vehicle ${name.padEnd(5)} services=${doc.services.join(',')} image=${doc.imageUrl || '(none — add in admin panel)'}`)
  }

  // A function, not a constant: each zone needs its own subdocument _ids, or
  // the two cities' packages would share ids and an edit by id could hit both.
  const pricingRows = () => PRICING.map(({ vehicle, ...p }) => ({
    _id: new mongoose.Types.ObjectId(),
    vehicleTypeId: vtByName[vehicle]._id,
    vehicleTypeName: vehicle,
    perMin: 0, perHour: 0, hireReturnCharge: 0, perKg: 0,
    nightHaltCharge: 0, emptyReturnPercent: 0, outPerHour: 0, rtBaseFare: 0, rtPerKm: 0, rtPerHour: 0,
    kmLimitPerDay: 0, extraKmRate: 0, driverAllowance: 0, gstPercent: 0,
    commissionPercent: COMMISSION_PERCENT, isActive: true,
    ...p,
  }))
  const rentalRows = () => RENTAL_PACKAGES.map(({ vehicle, ...p }) => ({
    _id: new mongoose.Types.ObjectId(),
    vehicleTypeId: vtByName[vehicle]._id,
    vehicleTypeName: vehicle,
    commissionPercent: COMMISSION_PERCENT, isActive: true,
    ...p,
  }))

  // Zones
  for (const city of CITIES) {
    let zone = await db.collection('zones').findOne({ name: city.name })
    if (!zone) {
      await db.collection('zones').insertOne({
        name: city.name, city: city.name, type: 'city', isActive: true,
        polygonPath: octagon(city), centerLat: city.lat, centerLng: city.lng,
        pricing: [], rentalPackages: [], createdAt: now, updatedAt: now,
      })
      zone = await db.collection('zones').findOne({ name: city.name })
      console.log(`zone ${city.name}: created with a default ${city.radiusKm} km boundary — redraw it in the admin panel`)
    }
    const set = { isActive: true, updatedAt: now }
    const hasPricing = (zone.pricing || []).length > 0
    const hasRental = (zone.rentalPackages || []).length > 0
    if (!hasPricing || FORCE) set.pricing = pricingRows()
    if (!hasRental || FORCE) set.rentalPackages = rentalRows()
    await db.collection('zones').updateOne({ _id: zone._id }, { $set: set })
    console.log(`zone ${city.name}: pricing ${set.pricing ? `set (${set.pricing.length} rows)` : 'kept (use --force to replace)'}, ` +
      `rental ${set.rentalPackages ? `set (${set.rentalPackages.length} packages)` : 'kept (use --force to replace)'}`)
  }

  // Service configs — insert only
  for (const [service, cancellationFee] of Object.entries(CANCELLATION_FEES)) {
    const r = await db.collection('serviceconfigs').updateOne(
      { service },
      { $setOnInsert: { service, isActive: true, cancellationFee, baseDistance: 2, waitingCharge: 1,
          priceType: 'both', extraConfig: {}, createdAt: now, updatedAt: now } },
      { upsert: true },
    )
    console.log(`service ${service.padEnd(11)} ${r.upsertedCount ? `created (cancellation fee ₹${cancellationFee})` : 'kept'}`)
  }

  // Admin SOS contacts — insert only
  for (const c of SOS_CONTACTS) {
    const r = await db.collection('soscontacts').updateOne(
      { phone: c.phone, addedBy: 'admin' },
      { $setOnInsert: { ...c, addedBy: 'admin', ownerId: null, isActive: true, createdAt: now, updatedAt: now } },
      { upsert: true },
    )
    console.log(`sos ${c.name.padEnd(14)} ${c.phone.padEnd(5)} ${r.upsertedCount ? 'created' : 'kept'}`)
  }

  await mongoose.disconnect()
}

main().catch((e) => { console.error('seed failed:', e.message); process.exit(1) })
