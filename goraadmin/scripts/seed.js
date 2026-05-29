const mongoose = require('mongoose')
const bcrypt = require('bcryptjs')

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/goraadmin'

// Inline schemas to avoid TypeScript compilation issues
const AdminSchema = new mongoose.Schema({
  name: String, email: { type: String, unique: true }, password: String, role: { type: String, default: 'admin' },
}, { timestamps: true })

const UserSchema = new mongoose.Schema({
  name: String, phone: { type: String, unique: true }, email: String,
  status: { type: String, default: 'active' }, walletBalance: { type: Number, default: 0 },
  totalRides: { type: Number, default: 0 },
}, { timestamps: true })

const DriverSchema = new mongoose.Schema({
  name: String, phone: { type: String, unique: true }, email: String,
  status: { type: String, default: 'pending' }, isOnline: { type: Boolean, default: false },
  vehicleNumber: String, vehicleModel: String, vehicleType: String,
  rating: { type: Number, default: 0 }, totalRides: { type: Number, default: 0 },
  totalEarnings: { type: Number, default: 0 }, walletBalance: { type: Number, default: 0 },
  documents: [{ name: String, fileUrl: String, status: { type: String, default: 'pending' }, expiryDate: String }],
}, { timestamps: true })

const VehicleTypeSchema = new mongoose.Schema({
  name: String, icon: String, capacity: Number, baseFare: Number,
  perKm: Number, perMin: Number, minFare: Number, isActive: { type: Boolean, default: true }, sortOrder: Number,
}, { timestamps: true })

const ZoneSchema = new mongoose.Schema({
  name: String, city: String, type: String, isActive: { type: Boolean, default: true }, pricing: Array,
}, { timestamps: true })

const RideSchema = new mongoose.Schema({
  riderId: mongoose.Schema.Types.ObjectId, riderName: String, riderPhone: String,
  driverId: mongoose.Schema.Types.ObjectId, driverName: String, driverPhone: String,
  pickupAddress: String, dropAddress: String, service: String, vehicleType: String,
  status: String, fare: Number, distance: Number, duration: Number,
  paymentMode: String, paymentStatus: String,
  scheduledAt: Date, startedAt: Date, completedAt: Date,
  cancelledBy: String, cancellationReason: String,
}, { timestamps: true })

const PromoSchema = new mongoose.Schema({
  code: { type: String, unique: true, uppercase: true }, type: String, value: Number,
  minOrderAmount: Number, maxDiscount: Number, maxUses: Number, usedCount: { type: Number, default: 0 },
  expiryDate: Date, isActive: { type: Boolean, default: true },
}, { timestamps: true })

const FAQSchema = new mongoose.Schema({
  question: String, answer: String, category: String, isActive: { type: Boolean, default: true }, sortOrder: Number,
}, { timestamps: true })

const ServiceConfigSchema = new mongoose.Schema({
  service: { type: String, unique: true }, isActive: { type: Boolean, default: true },
  baseFare: Number, perKm: Number, perMin: Number, minFare: Number,
  cancellationFee: Number, driverCommissionPercent: Number, nightSurchargePercent: Number,
  extraConfig: { type: mongoose.Schema.Types.Mixed, default: {} },
}, { timestamps: true })

const SettingsSchema = new mongoose.Schema({
  key: { type: String, unique: true, default: 'global' },
  general: mongoose.Schema.Types.Mixed,
  payment: mongoose.Schema.Types.Mixed,
  maps: mongoose.Schema.Types.Mixed,
  sms: mongoose.Schema.Types.Mixed,
  mail: mongoose.Schema.Types.Mixed,
  firebase: mongoose.Schema.Types.Mixed,
}, { timestamps: true })

const SOSSchema = new mongoose.Schema({
  name: String, phone: String, relation: String, addedBy: { type: String, default: 'admin' }, isActive: { type: Boolean, default: true },
}, { timestamps: true })

const Admin = mongoose.models.Admin || mongoose.model('Admin', AdminSchema)
const User = mongoose.models.User || mongoose.model('User', UserSchema)
const Driver = mongoose.models.Driver || mongoose.model('Driver', DriverSchema)
const VehicleType = mongoose.models.VehicleType || mongoose.model('VehicleType', VehicleTypeSchema)
const Zone = mongoose.models.Zone || mongoose.model('Zone', ZoneSchema)
const Ride = mongoose.models.Ride || mongoose.model('Ride', RideSchema)
const PromoCode = mongoose.models.PromoCode || mongoose.model('PromoCode', PromoSchema)
const FAQ = mongoose.models.FAQ || mongoose.model('FAQ', FAQSchema)
const ServiceConfig = mongoose.models.ServiceConfig || mongoose.model('ServiceConfig', ServiceConfigSchema)
const Settings = mongoose.models.Settings || mongoose.model('Settings', SettingsSchema)
const SOSContact = mongoose.models.SOSContact || mongoose.model('SOSContact', SOSSchema)

async function seed() {
  console.log('Connecting to MongoDB...')
  await mongoose.connect(MONGODB_URI)
  console.log('Connected!')

  // Clear existing data
  await Promise.all([
    Admin.deleteMany({}),
    User.deleteMany({}),
    Driver.deleteMany({}),
    VehicleType.deleteMany({}),
    Zone.deleteMany({}),
    Ride.deleteMany({}),
    PromoCode.deleteMany({}),
    FAQ.deleteMany({}),
    ServiceConfig.deleteMany({}),
    Settings.deleteMany({}),
    SOSContact.deleteMany({}),
  ])
  console.log('Cleared existing data')

  // Admin
  const hashedPassword = await bcrypt.hash('admin123', 10)
  await Admin.create({ name: 'Gora Admin', email: 'admin@gora.com', password: hashedPassword, role: 'admin' })
  console.log('Admin created: admin@gora.com / admin123')

  // Users
  const users = await User.insertMany([
    { name: 'Rahul Sharma', phone: '+91 98765 11001', email: 'rahul@example.com', status: 'active', walletBalance: 350, totalRides: 42 },
    { name: 'Priya Patel', phone: '+91 98765 11002', email: 'priya@example.com', status: 'active', walletBalance: 120, totalRides: 18 },
    { name: 'Amit Joshi', phone: '+91 98765 11003', email: 'amit@example.com', status: 'blocked', walletBalance: 0, totalRides: 5 },
    { name: 'Sneha Verma', phone: '+91 98765 11004', email: 'sneha@example.com', status: 'active', walletBalance: 800, totalRides: 67 },
    { name: 'Karan Mehta', phone: '+91 98765 11005', email: 'karan@example.com', status: 'active', walletBalance: 250, totalRides: 29 },
  ])
  console.log('Users seeded:', users.length)

  // Drivers
  const docs = [
    { name: 'Driving License', status: 'verified' },
    { name: 'RC Book', status: 'verified' },
    { name: 'Insurance', status: 'verified' },
    { name: 'PAN Card', status: 'verified' },
  ]
  const pendingDocs = [
    { name: 'Driving License', status: 'pending' },
    { name: 'RC Book', status: 'pending' },
    { name: 'Insurance', status: 'pending' },
    { name: 'PAN Card', status: 'pending' },
  ]
  const drivers = await Driver.insertMany([
    { name: 'Suresh Yadav', phone: '+91 97654 21001', email: 'suresh@example.com', status: 'approved', isOnline: true, vehicleNumber: 'GJ01AB1234', vehicleModel: 'Maruti Dzire', vehicleType: 'Sedan', rating: 4.8, totalRides: 320, totalEarnings: 85000, walletBalance: 5000, documents: docs },
    { name: 'Mohan Lal', phone: '+91 97654 21002', email: 'mohan@example.com', status: 'approved', isOnline: false, vehicleNumber: 'GJ01CD5678', vehicleModel: 'Bajaj RE Auto', vehicleType: 'Auto', rating: 4.5, totalRides: 215, totalEarnings: 52000, walletBalance: 3500, documents: docs },
    { name: 'Ramesh Gupta', phone: '+91 97654 21003', email: 'ramesh@example.com', status: 'pending', isOnline: false, vehicleNumber: 'GJ01EF9012', vehicleModel: 'Mahindra XUV500', vehicleType: 'SUV', rating: 0, totalRides: 0, totalEarnings: 0, walletBalance: 0, documents: pendingDocs },
    { name: 'Dinesh Patil', phone: '+91 97654 21004', email: 'dinesh@example.com', status: 'approved', isOnline: true, vehicleNumber: 'GJ02AB3456', vehicleModel: 'Honda City', vehicleType: 'Sedan', rating: 4.7, totalRides: 189, totalEarnings: 48000, walletBalance: 7000, documents: docs },
    { name: 'Vijay Kumar', phone: '+91 97654 21010', email: 'vijay@example.com', status: 'pending', isOnline: false, vehicleNumber: 'GJ05AB5555', vehicleModel: 'Maruti Alto', vehicleType: 'Mini', rating: 0, totalRides: 0, totalEarnings: 0, walletBalance: 0, documents: pendingDocs },
  ])
  console.log('Drivers seeded:', drivers.length)

  // Vehicle Types
  await VehicleType.insertMany([
    { name: 'Auto', icon: '🛺', capacity: 3, baseFare: 25, perKm: 12, perMin: 1.5, minFare: 40, isActive: true, sortOrder: 1 },
    { name: 'Sedan', icon: '🚗', capacity: 4, baseFare: 50, perKm: 15, perMin: 2, minFare: 70, isActive: true, sortOrder: 2 },
    { name: 'SUV', icon: '🚙', capacity: 6, baseFare: 80, perKm: 20, perMin: 2.5, minFare: 100, isActive: true, sortOrder: 3 },
    { name: 'Bike', icon: '🏍️', capacity: 1, baseFare: 20, perKm: 8, perMin: 1, minFare: 30, isActive: true, sortOrder: 4 },
    { name: 'Mini', icon: '🚕', capacity: 4, baseFare: 40, perKm: 13, perMin: 1.8, minFare: 60, isActive: true, sortOrder: 5 },
  ])
  console.log('Vehicle types seeded')

  // Zones
  await Zone.insertMany([
    { name: 'Ahmedabad City', city: 'Ahmedabad', type: 'city', isActive: true, pricing: [] },
    { name: 'Airport Zone', city: 'Ahmedabad', type: 'airport', isActive: true, pricing: [] },
  ])
  console.log('Zones seeded')

  // Rides
  const now = new Date()
  await Ride.insertMany([
    { riderId: users[0]._id, riderName: 'Rahul Sharma', riderPhone: '+91 98765 11001', driverId: drivers[0]._id, driverName: 'Suresh Yadav', driverPhone: '+91 97654 21001', pickupAddress: 'Navrangpura', dropAddress: 'Satellite', service: 'taxi', vehicleType: 'Sedan', status: 'completed', fare: 185, distance: 8, duration: 22, paymentMode: 'online', paymentStatus: 'paid', completedAt: new Date(now - 2*60*60*1000) },
    { riderId: users[1]._id, riderName: 'Priya Patel', riderPhone: '+91 98765 11002', driverId: drivers[1]._id, driverName: 'Mohan Lal', driverPhone: '+91 97654 21002', pickupAddress: 'Bopal', dropAddress: 'Airport', service: 'taxi', vehicleType: 'Auto', status: 'completed', fare: 320, distance: 15, duration: 35, paymentMode: 'cash', paymentStatus: 'paid', completedAt: new Date(now - 4*60*60*1000) },
    { riderId: users[2]._id, riderName: 'Amit Joshi', riderPhone: '+91 98765 11003', driverId: drivers[3]._id, driverName: 'Dinesh Patil', driverPhone: '+91 97654 21004', pickupAddress: 'Vastrapur', dropAddress: 'CG Road', service: 'taxi', vehicleType: 'Sedan', status: 'cancelled', fare: 95, cancelledBy: 'rider', cancellationReason: 'Changed my mind', paymentMode: 'wallet', paymentStatus: 'pending' },
    { riderId: users[3]._id, riderName: 'Sneha Verma', riderPhone: '+91 98765 11004', driverId: drivers[0]._id, driverName: 'Suresh Yadav', driverPhone: '+91 97654 21001', pickupAddress: 'SG Highway', dropAddress: 'Maninagar', service: 'rental', vehicleType: 'Sedan', status: 'completed', fare: 450, distance: 22, duration: 60, paymentMode: 'online', paymentStatus: 'paid', completedAt: new Date(now - 6*60*60*1000) },
    { riderId: users[4]._id, riderName: 'Karan Mehta', riderPhone: '+91 98765 11005', driverId: drivers[3]._id, driverName: 'Dinesh Patil', driverPhone: '+91 97654 21004', pickupAddress: 'Bodakdev', dropAddress: 'Iskon', service: 'outstation', vehicleType: 'Sedan', status: 'ongoing', fare: 1800, distance: 120, duration: 180, paymentMode: 'online', paymentStatus: 'pending', startedAt: new Date(now - 90*60*1000) },
    { riderId: users[0]._id, riderName: 'Rahul Sharma', riderPhone: '+91 98765 11001', driverId: drivers[1]._id, driverName: 'Mohan Lal', driverPhone: '+91 97654 21002', pickupAddress: 'Thaltej', dropAddress: 'Sarkhej', service: 'taxi', vehicleType: 'Auto', status: 'completed', fare: 210, distance: 10, duration: 25, paymentMode: 'online', paymentStatus: 'paid', completedAt: new Date(now - 24*60*60*1000) },
    { riderId: users[1]._id, riderName: 'Priya Patel', riderPhone: '+91 98765 11002', driverId: drivers[0]._id, driverName: 'Suresh Yadav', driverPhone: '+91 97654 21001', pickupAddress: 'Chandkheda', dropAddress: 'Naroda', service: 'taxi', vehicleType: 'Sedan', status: 'cancelled', fare: 130, cancelledBy: 'driver', cancellationReason: 'Traffic congestion', paymentMode: 'cash', paymentStatus: 'pending' },
    { riderId: users[3]._id, riderName: 'Sneha Verma', riderPhone: '+91 98765 11004', driverId: drivers[3]._id, driverName: 'Dinesh Patil', driverPhone: '+91 97654 21004', pickupAddress: 'Paldi', dropAddress: 'Ellisbridge', service: 'delivery', vehicleType: 'Bike', status: 'completed', fare: 75, distance: 3, duration: 15, paymentMode: 'wallet', paymentStatus: 'paid', completedAt: new Date(now - 48*60*60*1000) },
    { riderId: users[4]._id, riderName: 'Karan Mehta', riderPhone: '+91 98765 11005', driverId: drivers[1]._id, driverName: 'Mohan Lal', driverPhone: '+91 97654 21002', pickupAddress: 'Gota', dropAddress: 'Ranip', service: 'taxi', vehicleType: 'Auto', status: 'completed', fare: 90, distance: 5, duration: 18, paymentMode: 'online', paymentStatus: 'paid', completedAt: new Date(now - 72*60*60*1000) },
    { riderId: users[2]._id, riderName: 'Amit Joshi', riderPhone: '+91 98765 11003', driverId: drivers[0]._id, driverName: 'Suresh Yadav', driverPhone: '+91 97654 21001', pickupAddress: 'Vastral', dropAddress: 'Bapunagar', service: 'taxi', vehicleType: 'Sedan', status: 'pending', fare: 120, paymentMode: 'online', paymentStatus: 'pending', scheduledAt: new Date(now.getTime() + 2*60*60*1000) },
  ])
  console.log('Rides seeded')

  // Promos
  await PromoCode.insertMany([
    { code: 'FIRST50', type: 'percent', value: 50, minOrderAmount: 100, maxDiscount: 200, maxUses: 1000, usedCount: 234, expiryDate: new Date('2025-03-31'), isActive: true },
    { code: 'FLAT100', type: 'flat', value: 100, minOrderAmount: 300, maxDiscount: 100, maxUses: 500, usedCount: 312, expiryDate: new Date('2025-06-30'), isActive: true },
    { code: 'WEEKEND20', type: 'percent', value: 20, minOrderAmount: 150, maxDiscount: 500, maxUses: 2000, usedCount: 891, expiryDate: new Date('2025-12-31'), isActive: true },
  ])
  console.log('Promo codes seeded')

  // FAQs
  await FAQ.insertMany([
    { question: 'How do I book a ride?', answer: 'Open the Gora Cabs app, enter your pickup and drop location, choose your vehicle type, and tap "Book Ride". A driver will be assigned within minutes.', category: 'rider', isActive: true, sortOrder: 1 },
    { question: 'How do I pay for my ride?', answer: 'You can pay using UPI, credit/debit card, cash, or your Gora wallet. Select your preferred payment method before confirming the booking.', category: 'payment', isActive: true, sortOrder: 2 },
    { question: 'How do I become a driver?', answer: 'Download the Gora Driver app, register with your documents (license, RC, insurance), and wait for verification. Usually takes 24-48 hours.', category: 'driver', isActive: true, sortOrder: 3 },
    { question: 'How are fares calculated?', answer: 'Fares are calculated based on base fare + per km rate + per minute rate. Surge pricing may apply during peak hours.', category: 'general', isActive: true, sortOrder: 4 },
  ])
  console.log('FAQs seeded')

  // Service Configs
  await ServiceConfig.insertMany([
    { service: 'taxi', isActive: true, baseFare: 50, perKm: 15, perMin: 2, minFare: 70, cancellationFee: 30, driverCommissionPercent: 80, nightSurchargePercent: 20 },
    { service: 'rental', isActive: true, baseFare: 200, perKm: 10, perMin: 3, minFare: 200, cancellationFee: 50, driverCommissionPercent: 80, nightSurchargePercent: 10 },
    { service: 'outstation', isActive: true, baseFare: 500, perKm: 12, perMin: 0, minFare: 500, cancellationFee: 100, driverCommissionPercent: 85, nightSurchargePercent: 0 },
    { service: 'delivery', isActive: true, baseFare: 30, perKm: 8, perMin: 1, minFare: 40, cancellationFee: 20, driverCommissionPercent: 75, nightSurchargePercent: 15 },
    { service: 'goods', isActive: false, baseFare: 100, perKm: 20, perMin: 2, minFare: 150, cancellationFee: 50, driverCommissionPercent: 75, nightSurchargePercent: 10 },
  ])
  console.log('Service configs seeded')

  // Default Settings
  await Settings.create({
    key: 'global',
    general: { appName: 'Gora Cabs', currency: 'INR', currencySymbol: '₹', country: 'India', timezone: 'Asia/Kolkata', supportEmail: 'support@goracabs.com', supportPhone: '+91 98765 43210' },
    payment: { razorpay: { enabled: true, keyId: '', keySecret: '' }, stripe: { enabled: false, publishableKey: '', secretKey: '' }, cashEnabled: true, walletEnabled: true, commissionPercent: 20 },
    maps: { provider: 'google', googleMapsApiKey: '', mapboxToken: '' },
    sms: { provider: 'twilio', twilio: { accountSid: '', authToken: '', fromNumber: '' }, msg91: { authKey: '', senderId: '' } },
    mail: { driver: 'smtp', host: 'smtp.gmail.com', port: 587, username: '', password: '', fromName: 'Gora Cabs', fromEmail: 'noreply@goracabs.com' },
    firebase: { serverKey: '', projectId: '' },
  })
  console.log('Settings seeded')

  // SOS Contacts
  await SOSContact.insertMany([
    { name: 'Ahmedabad Police', phone: '100', relation: 'Emergency', addedBy: 'admin', isActive: true },
    { name: 'Women Helpline', phone: '1091', relation: 'Emergency', addedBy: 'admin', isActive: true },
    { name: 'Ambulance', phone: '108', relation: 'Emergency', addedBy: 'admin', isActive: true },
    { name: 'Gora Support 24/7', phone: '+91 99887 00000', relation: 'App Support', addedBy: 'admin', isActive: true },
  ])
  console.log('SOS contacts seeded')

  console.log('\n✅ Database seeded successfully!')
  process.exit(0)
}

seed().catch(err => {
  console.error('Seed failed:', err)
  process.exit(1)
})
