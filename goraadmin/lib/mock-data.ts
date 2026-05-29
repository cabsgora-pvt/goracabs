export const users = [
  { id: '1', name: 'Rahul Sharma', phone: '+91 98765 11001', email: 'rahul@example.com', status: 'active', walletBalance: 350, totalRides: 42, joinDate: '2023-06-15' },
  { id: '2', name: 'Priya Patel', phone: '+91 98765 11002', email: 'priya@example.com', status: 'active', walletBalance: 120, totalRides: 18, joinDate: '2023-07-22' },
  { id: '3', name: 'Amit Joshi', phone: '+91 98765 11003', email: 'amit@example.com', status: 'blocked', walletBalance: 0, totalRides: 5, joinDate: '2023-08-10' },
  { id: '4', name: 'Sneha Verma', phone: '+91 98765 11004', email: 'sneha@example.com', status: 'active', walletBalance: 800, totalRides: 67, joinDate: '2023-05-01' },
  { id: '5', name: 'Karan Mehta', phone: '+91 98765 11005', email: 'karan@example.com', status: 'active', walletBalance: 250, totalRides: 29, joinDate: '2023-09-18' },
  { id: '6', name: 'Pooja Singh', phone: '+91 98765 11006', email: 'pooja@example.com', status: 'active', walletBalance: 450, totalRides: 55, joinDate: '2023-04-25' },
  { id: '7', name: 'Vikram Rao', phone: '+91 98765 11007', email: 'vikram@example.com', status: 'blocked', walletBalance: 0, totalRides: 3, joinDate: '2023-10-05' },
  { id: '8', name: 'Divya Nair', phone: '+91 98765 11008', email: 'divya@example.com', status: 'active', walletBalance: 620, totalRides: 81, joinDate: '2023-03-14' },
  { id: '9', name: 'Rajesh Kumar', phone: '+91 98765 11009', email: 'rajesh@example.com', status: 'active', walletBalance: 175, totalRides: 22, joinDate: '2023-11-02' },
  { id: '10', name: 'Anita Desai', phone: '+91 98765 11010', email: 'anita@example.com', status: 'active', walletBalance: 990, totalRides: 104, joinDate: '2023-02-28' },
]

export const drivers = [
  { id: 'd1', name: 'Suresh Yadav', phone: '+91 97654 21001', vehicleNumber: 'GJ01AB1234', vehicleType: 'Sedan', status: 'approved', rating: 4.8, totalRides: 320, earnings: 85000, documents: [{ name: 'Driving License', status: 'verified' }, { name: 'RC Book', status: 'verified' }, { name: 'Insurance', status: 'verified' }, { name: 'PAN Card', status: 'verified' }], joinDate: '2023-01-10' },
  { id: 'd2', name: 'Mohan Lal', phone: '+91 97654 21002', vehicleNumber: 'GJ01CD5678', vehicleType: 'Auto', status: 'approved', rating: 4.5, totalRides: 215, earnings: 52000, documents: [{ name: 'Driving License', status: 'verified' }, { name: 'RC Book', status: 'verified' }, { name: 'Insurance', status: 'pending' }, { name: 'PAN Card', status: 'verified' }], joinDate: '2023-02-20' },
  { id: 'd3', name: 'Ramesh Gupta', phone: '+91 97654 21003', vehicleNumber: 'GJ01EF9012', vehicleType: 'SUV', status: 'pending', rating: 0, totalRides: 0, earnings: 0, documents: [{ name: 'Driving License', status: 'pending' }, { name: 'RC Book', status: 'pending' }, { name: 'Insurance', status: 'pending' }, { name: 'PAN Card', status: 'pending' }], joinDate: '2024-01-05' },
  { id: 'd4', name: 'Dinesh Patil', phone: '+91 97654 21004', vehicleNumber: 'GJ02AB3456', vehicleType: 'Sedan', status: 'approved', rating: 4.7, totalRides: 189, earnings: 48000, documents: [{ name: 'Driving License', status: 'verified' }, { name: 'RC Book', status: 'verified' }, { name: 'Insurance', status: 'verified' }, { name: 'PAN Card', status: 'verified' }], joinDate: '2023-03-15' },
  { id: 'd5', name: 'Harish Tiwari', phone: '+91 97654 21005', vehicleNumber: 'GJ02CD7890', vehicleType: 'Bike', status: 'blocked', rating: 3.2, totalRides: 45, earnings: 8000, documents: [{ name: 'Driving License', status: 'verified' }, { name: 'RC Book', status: 'verified' }, { name: 'Insurance', status: 'rejected' }, { name: 'PAN Card', status: 'verified' }], joinDate: '2023-04-01' },
  { id: 'd6', name: 'Prakash Sharma', phone: '+91 97654 21006', vehicleNumber: 'GJ03AB1111', vehicleType: 'Mini', status: 'approved', rating: 4.9, totalRides: 445, earnings: 112000, documents: [{ name: 'Driving License', status: 'verified' }, { name: 'RC Book', status: 'verified' }, { name: 'Insurance', status: 'verified' }, { name: 'PAN Card', status: 'verified' }], joinDate: '2022-12-01' },
  { id: 'd7', name: 'Nilesh Patel', phone: '+91 97654 21007', vehicleNumber: 'GJ03CD2222', vehicleType: 'Electric', status: 'pending', rating: 0, totalRides: 0, earnings: 0, documents: [{ name: 'Driving License', status: 'verified' }, { name: 'RC Book', status: 'pending' }, { name: 'Insurance', status: 'pending' }, { name: 'PAN Card', status: 'verified' }], joinDate: '2024-01-10' },
  { id: 'd8', name: 'Sanjay Desai', phone: '+91 97654 21008', vehicleNumber: 'GJ04AB3333', vehicleType: 'Prime Sedan', status: 'approved', rating: 4.6, totalRides: 278, earnings: 92000, documents: [{ name: 'Driving License', status: 'verified' }, { name: 'RC Book', status: 'verified' }, { name: 'Insurance', status: 'verified' }, { name: 'PAN Card', status: 'verified' }], joinDate: '2023-05-20' },
  { id: 'd9', name: 'Ajay Mishra', phone: '+91 97654 21009', vehicleNumber: 'GJ04CD4444', vehicleType: 'XL', status: 'approved', rating: 4.4, totalRides: 156, earnings: 58000, documents: [{ name: 'Driving License', status: 'verified' }, { name: 'RC Book', status: 'verified' }, { name: 'Insurance', status: 'verified' }, { name: 'PAN Card', status: 'verified' }], joinDate: '2023-06-30' },
  { id: 'd10', name: 'Vijay Kumar', phone: '+91 97654 21010', vehicleNumber: 'GJ05AB5555', vehicleType: 'Auto', status: 'pending', rating: 0, totalRides: 0, earnings: 0, documents: [{ name: 'Driving License', status: 'pending' }, { name: 'RC Book', status: 'verified' }, { name: 'Insurance', status: 'pending' }, { name: 'PAN Card', status: 'pending' }], joinDate: '2024-01-15' },
]

export const vehicleTypes = [
  { id: 'vt1', name: 'Auto', icon: '🛺', capacity: 3, baseFare: 25, perKm: 12, perMin: 1.5, minFare: 40, status: 'active' },
  { id: 'vt2', name: 'Sedan', icon: '🚗', capacity: 4, baseFare: 50, perKm: 15, perMin: 2, minFare: 70, status: 'active' },
  { id: 'vt3', name: 'SUV', icon: '🚙', capacity: 6, baseFare: 80, perKm: 20, perMin: 2.5, minFare: 100, status: 'active' },
  { id: 'vt4', name: 'Bike', icon: '🏍️', capacity: 1, baseFare: 20, perKm: 8, perMin: 1, minFare: 30, status: 'active' },
  { id: 'vt5', name: 'Mini', icon: '🚕', capacity: 4, baseFare: 40, perKm: 13, perMin: 1.8, minFare: 60, status: 'active' },
  { id: 'vt6', name: 'Prime Sedan', icon: '🚘', capacity: 4, baseFare: 70, perKm: 18, perMin: 2.2, minFare: 90, status: 'active' },
  { id: 'vt7', name: 'XL', icon: '🚐', capacity: 7, baseFare: 100, perKm: 22, perMin: 3, minFare: 130, status: 'active' },
  { id: 'vt8', name: 'Electric', icon: '⚡', capacity: 4, baseFare: 45, perKm: 11, perMin: 1.6, minFare: 65, status: 'active' },
]

export const zones = [
  { id: 'z1', name: 'Ahmedabad City', city: 'Ahmedabad', type: 'city', status: 'active', driverCount: 145, coordinates: '23.0225° N, 72.5714° E' },
  { id: 'z2', name: 'Airport Zone', city: 'Ahmedabad', type: 'airport', status: 'active', driverCount: 32, coordinates: '23.0776° N, 72.6347° E' },
  { id: 'z3', name: 'Outskirts', city: 'Ahmedabad', type: 'outskirts', status: 'active', driverCount: 28, coordinates: '22.9500° N, 72.4800° E' },
  { id: 'z4', name: 'Industrial Area', city: 'Ahmedabad', type: 'industrial', status: 'active', driverCount: 45, coordinates: '23.0500° N, 72.6000° E' },
  { id: 'z5', name: 'IT Hub', city: 'Ahmedabad', type: 'commercial', status: 'active', driverCount: 67, coordinates: '23.0390° N, 72.5050° E' },
]

export const rides = [
  { id: 'R001', rider: 'Rahul Sharma', driver: 'Suresh Yadav', pickup: 'Navrangpura', drop: 'Satellite', service: 'Taxi', fare: 185, status: 'completed', date: '2024-01-20 10:30', paymentMode: 'UPI' },
  { id: 'R002', rider: 'Priya Patel', driver: 'Mohan Lal', pickup: 'Bopal', drop: 'Airport', service: 'Taxi', fare: 320, status: 'completed', date: '2024-01-20 11:15', paymentMode: 'Cash' },
  { id: 'R003', rider: 'Amit Joshi', driver: 'Dinesh Patil', pickup: 'Vastrapur', drop: 'CG Road', service: 'Taxi', fare: 95, status: 'cancelled', date: '2024-01-20 12:00', paymentMode: 'Wallet' },
  { id: 'R004', rider: 'Sneha Verma', driver: 'Prakash Sharma', pickup: 'SG Highway', drop: 'Maninagar', service: 'Rental', fare: 450, status: 'completed', date: '2024-01-20 13:30', paymentMode: 'Card' },
  { id: 'R005', rider: 'Karan Mehta', driver: 'Sanjay Desai', pickup: 'Bodakdev', drop: 'Iskon', service: 'Outstation', fare: 1800, status: 'ongoing', date: '2024-01-20 14:00', paymentMode: 'UPI' },
  { id: 'R006', rider: 'Pooja Singh', driver: 'Ajay Mishra', pickup: 'Thaltej', drop: 'Sarkhej', service: 'Taxi', fare: 210, status: 'completed', date: '2024-01-19 09:00', paymentMode: 'UPI' },
  { id: 'R007', rider: 'Vikram Rao', driver: 'Suresh Yadav', pickup: 'Chandkheda', drop: 'Naroda', service: 'Taxi', fare: 130, status: 'cancelled', date: '2024-01-19 10:30', paymentMode: 'Cash' },
  { id: 'R008', rider: 'Divya Nair', driver: 'Mohan Lal', pickup: 'Paldi', drop: 'Ellisbridge', service: 'Delivery', fare: 75, status: 'completed', date: '2024-01-19 11:45', paymentMode: 'Wallet' },
  { id: 'R009', rider: 'Rajesh Kumar', driver: 'Harish Tiwari', pickup: 'Gota', drop: 'Ranip', service: 'Taxi', fare: 90, status: 'completed', date: '2024-01-19 14:00', paymentMode: 'UPI' },
  { id: 'R010', rider: 'Anita Desai', driver: 'Nilesh Patel', pickup: 'Vastral', drop: 'Bapunagar', service: 'Taxi', fare: 120, status: 'scheduled', date: '2024-01-21 08:00', paymentMode: 'UPI' },
  { id: 'R011', rider: 'Rahul Sharma', driver: 'Vijay Kumar', pickup: 'Naranpura', drop: 'Memnagar', service: 'Taxi', fare: 85, status: 'completed', date: '2024-01-18 09:30', paymentMode: 'Cash' },
  { id: 'R012', rider: 'Priya Patel', driver: 'Dinesh Patil', pickup: 'New Ranip', drop: 'Sola', service: 'Taxi', fare: 145, status: 'completed', date: '2024-01-18 11:00', paymentMode: 'UPI' },
  { id: 'R013', rider: 'Sneha Verma', driver: 'Prakash Sharma', pickup: 'Jivraj Park', drop: 'Ghatlodiya', service: 'Rental', fare: 600, status: 'completed', date: '2024-01-18 13:00', paymentMode: 'Card' },
  { id: 'R014', rider: 'Karan Mehta', driver: 'Sanjay Desai', pickup: 'Vejalpur', drop: 'Ramol', service: 'Taxi', fare: 175, status: 'cancelled', date: '2024-01-18 15:00', paymentMode: 'Wallet' },
  { id: 'R015', rider: 'Pooja Singh', driver: 'Ajay Mishra', pickup: 'Odhav', drop: 'Kathwada', service: 'Taxi', fare: 110, status: 'completed', date: '2024-01-17 10:00', paymentMode: 'UPI' },
  { id: 'R016', rider: 'Divya Nair', driver: 'Suresh Yadav', pickup: 'Science City', drop: 'Sarthana', service: 'Outstation', fare: 2200, status: 'completed', date: '2024-01-17 07:00', paymentMode: 'Card' },
  { id: 'R017', rider: 'Rajesh Kumar', driver: 'Mohan Lal', pickup: 'Bhat', drop: 'Khoraj', service: 'Delivery', fare: 95, status: 'completed', date: '2024-01-17 12:00', paymentMode: 'Cash' },
  { id: 'R018', rider: 'Anita Desai', driver: 'Dinesh Patil', pickup: 'Sanand', drop: 'Ahmedabad City', service: 'Outstation', fare: 950, status: 'completed', date: '2024-01-16 09:00', paymentMode: 'UPI' },
  { id: 'R019', rider: 'Amit Joshi', driver: 'Prakash Sharma', pickup: 'Bavla', drop: 'Ahmedabad City', service: 'Outstation', fare: 1100, status: 'scheduled', date: '2024-01-22 06:00', paymentMode: 'UPI' },
  { id: 'R020', rider: 'Vikram Rao', driver: 'Sanjay Desai', pickup: 'Mehsana Rd', drop: 'Naroda GIDC', service: 'Taxi', fare: 160, status: 'completed', date: '2024-01-16 14:30', paymentMode: 'Card' },
]

export const fleetOwners = [
  { id: 'fo1', name: 'Gujarat Cabs Pvt Ltd', phone: '+91 99887 11001', email: 'gujaratcabs@email.com', totalVehicles: 12, totalDrivers: 10, commissionPercent: 15, status: 'active' },
  { id: 'fo2', name: 'Ahmedabad Transport Co', phone: '+91 99887 11002', email: 'amdtransport@email.com', totalVehicles: 8, totalDrivers: 7, commissionPercent: 18, status: 'active' },
  { id: 'fo3', name: 'City Rides Fleet', phone: '+91 99887 11003', email: 'cityrides@email.com', totalVehicles: 5, totalDrivers: 5, commissionPercent: 20, status: 'active' },
  { id: 'fo4', name: 'Prime Wheels Ltd', phone: '+91 99887 11004', email: 'primewheels@email.com', totalVehicles: 20, totalDrivers: 18, commissionPercent: 12, status: 'active' },
  { id: 'fo5', name: 'Express Auto Services', phone: '+91 99887 11005', email: 'expressauto@email.com', totalVehicles: 3, totalDrivers: 3, commissionPercent: 22, status: 'inactive' },
]

export const promoCodes = [
  { id: 'p1', code: 'FIRST50', discountType: 'percent', value: 50, minOrder: 100, maxUses: 1000, usedCount: 234, expiry: '2024-03-31', status: 'active' },
  { id: 'p2', code: 'FLAT100', discountType: 'flat', value: 100, minOrder: 300, maxUses: 500, usedCount: 312, expiry: '2024-02-28', status: 'active' },
  { id: 'p3', code: 'WEEKEND20', discountType: 'percent', value: 20, minOrder: 150, maxUses: 2000, usedCount: 891, expiry: '2024-12-31', status: 'active' },
  { id: 'p4', code: 'GORA25', discountType: 'percent', value: 25, minOrder: 200, maxUses: 300, usedCount: 300, expiry: '2024-01-31', status: 'expired' },
  { id: 'p5', code: 'MONSOON30', discountType: 'percent', value: 30, minOrder: 120, maxUses: 1500, usedCount: 45, expiry: '2024-09-30', status: 'active' },
]

export const supportTickets = [
  { id: 'T001', user: 'Rahul Sharma', subject: 'Driver was rude', category: 'Complaint', priority: 'high', status: 'open', date: '2024-01-20', thread: [{ from: 'Rahul Sharma', message: 'The driver was very rude and refused to go to my destination.', time: '2024-01-20 10:00' }] },
  { id: 'T002', user: 'Priya Patel', subject: 'Overcharged for ride', category: 'Billing', priority: 'medium', status: 'in-progress', date: '2024-01-19', thread: [{ from: 'Priya Patel', message: 'I was charged ₹320 but the app showed ₹250.', time: '2024-01-19 15:00' }, { from: 'Support', message: 'We are investigating this issue. Will resolve in 24hrs.', time: '2024-01-19 16:00' }] },
  { id: 'T003', user: 'Amit Joshi', subject: 'App crash on booking', category: 'Technical', priority: 'high', status: 'open', date: '2024-01-20', thread: [{ from: 'Amit Joshi', message: 'App crashes every time I try to book a ride.', time: '2024-01-20 09:00' }] },
  { id: 'T004', user: 'Sneha Verma', subject: 'Refund not received', category: 'Billing', priority: 'medium', status: 'resolved', date: '2024-01-18', thread: [{ from: 'Sneha Verma', message: 'My refund of ₹200 has not been received yet.', time: '2024-01-18 11:00' }, { from: 'Support', message: 'Refund processed. Will reflect in 3-5 days.', time: '2024-01-18 14:00' }] },
  { id: 'T005', user: 'Karan Mehta', subject: 'Driver did not arrive', category: 'Complaint', priority: 'low', status: 'resolved', date: '2024-01-17', thread: [{ from: 'Karan Mehta', message: 'Driver accepted but never arrived.', time: '2024-01-17 08:00' }] },
  { id: 'T006', user: 'Pooja Singh', subject: 'Wrong route taken', category: 'Complaint', priority: 'medium', status: 'in-progress', date: '2024-01-20', thread: [{ from: 'Pooja Singh', message: 'Driver took a longer route and charged more.', time: '2024-01-20 12:00' }] },
  { id: 'T007', user: 'Vikram Rao', subject: 'Account locked', category: 'Technical', priority: 'high', status: 'open', date: '2024-01-20', thread: [{ from: 'Vikram Rao', message: 'Cannot login to my account. Shows "account suspended".', time: '2024-01-20 08:30' }] },
  { id: 'T008', user: 'Divya Nair', subject: 'Promo code not working', category: 'Billing', priority: 'low', status: 'resolved', date: '2024-01-16', thread: [{ from: 'Divya Nair', message: 'FIRST50 code shows invalid.', time: '2024-01-16 17:00' }] },
  { id: 'T009', user: 'Rajesh Kumar', subject: 'GPS not accurate', category: 'Technical', priority: 'medium', status: 'open', date: '2024-01-19', thread: [{ from: 'Rajesh Kumar', message: 'App shows wrong location on map.', time: '2024-01-19 10:00' }] },
  { id: 'T010', user: 'Anita Desai', subject: 'Request for receipt', category: 'Billing', priority: 'low', status: 'resolved', date: '2024-01-15', thread: [{ from: 'Anita Desai', message: 'Need receipt for ride R010 for reimbursement.', time: '2024-01-15 14:00' }] },
]

export const faqs = [
  { id: 'f1', question: 'How do I book a ride?', answer: 'Open the Gora Cabs app, enter your pickup and drop location, choose your vehicle type, and tap "Book Ride". A driver will be assigned within minutes.', category: 'Booking' },
  { id: 'f2', question: 'How do I pay for my ride?', answer: 'You can pay using UPI, credit/debit card, cash, or your Gora wallet. Select your preferred payment method before confirming the booking.', category: 'Payment' },
  { id: 'f3', question: 'Can I cancel my booking?', answer: 'Yes, you can cancel before the driver arrives. Cancellation within 2 minutes is free. After that, a cancellation fee may apply.', category: 'Booking' },
  { id: 'f4', question: 'How do I add money to my wallet?', answer: 'Go to Profile > Wallet > Add Money. Select the amount and complete the payment using UPI or card.', category: 'Payment' },
  { id: 'f5', question: 'What if I left something in the cab?', answer: 'Contact support immediately with your ride ID. We will connect you with the driver to retrieve your belongings.', category: 'Support' },
  { id: 'f6', question: 'How are fares calculated?', answer: 'Fares are calculated based on base fare + per km rate + per minute rate. Surge pricing may apply during peak hours.', category: 'Pricing' },
  { id: 'f7', question: 'Is it safe to ride with Gora?', answer: 'Yes! All drivers are verified with background checks. You can share your live trip with family. SOS button is available in the app.', category: 'Safety' },
  { id: 'f8', question: 'How do I become a driver?', answer: 'Download the Gora Driver app, register with your documents (license, RC, insurance), and wait for verification. Usually takes 24-48 hours.', category: 'Driver' },
  { id: 'f9', question: 'What documents are needed to register as a driver?', answer: 'Driving license, vehicle RC book, vehicle insurance, PAN card, and a selfie photo are required.', category: 'Driver' },
  { id: 'f10', question: 'How do I get a refund?', answer: 'For billing issues, contact support within 24 hours of the ride. Verified refunds are processed within 3-5 business days.', category: 'Payment' },
]

export const banners = [
  { id: 'b1', title: 'New User Offer', screen: 'Home', imageUrl: '', link: '/promo/new-user', status: 'active', color: '#1565C0' },
  { id: 'b2', title: 'Weekend Special', screen: 'Promo', imageUrl: '', link: '/promo/weekend', status: 'active', color: '#E53935' },
  { id: 'b3', title: 'App Launch Sale', screen: 'Splash', imageUrl: '', link: '/promo/launch', status: 'inactive', color: '#43A047' },
  { id: 'b4', title: 'Outstation Deals', screen: 'Home', imageUrl: '', link: '/promo/outstation', status: 'active', color: '#FB8C00' },
  { id: 'b5', title: 'Refer & Earn', screen: 'Home', imageUrl: '', link: '/referral', status: 'active', color: '#8E24AA' },
]

export const earningsData = [
  { date: 'Jan 14', rides: 42, revenue: 8400, commission: 1680 },
  { date: 'Jan 15', rides: 58, revenue: 11600, commission: 2320 },
  { date: 'Jan 16', rides: 35, revenue: 7000, commission: 1400 },
  { date: 'Jan 17', rides: 67, revenue: 13400, commission: 2680 },
  { date: 'Jan 18', rides: 72, revenue: 14400, commission: 2880 },
  { date: 'Jan 19', rides: 89, revenue: 17800, commission: 3560 },
  { date: 'Jan 20', rides: 94, revenue: 18800, commission: 3760 },
]

export const serviceEarningsData = [
  { service: 'Taxi', revenue: 52000 },
  { service: 'Rental', revenue: 18000 },
  { service: 'Outstation', revenue: 35000 },
  { service: 'Delivery', revenue: 8000 },
]

export const withdrawalRequests = [
  { id: 'w1', driver: 'Suresh Yadav', amount: 5000, bank: 'SBI **** 4321', requestedDate: '2024-01-20', status: 'pending' },
  { id: 'w2', driver: 'Mohan Lal', amount: 3500, bank: 'HDFC **** 8765', requestedDate: '2024-01-20', status: 'pending' },
  { id: 'w3', driver: 'Dinesh Patil', amount: 7000, bank: 'ICICI **** 2345', requestedDate: '2024-01-19', status: 'approved' },
  { id: 'w4', driver: 'Prakash Sharma', amount: 12000, bank: 'Axis **** 6789', requestedDate: '2024-01-19', status: 'approved' },
  { id: 'w5', driver: 'Sanjay Desai', amount: 8500, bank: 'Kotak **** 3456', requestedDate: '2024-01-18', status: 'approved' },
  { id: 'w6', driver: 'Ajay Mishra', amount: 4200, bank: 'PNB **** 7890', requestedDate: '2024-01-18', status: 'rejected' },
  { id: 'w7', driver: 'Harish Tiwari', amount: 2000, bank: 'BOB **** 1234', requestedDate: '2024-01-17', status: 'approved' },
  { id: 'w8', driver: 'Vijay Kumar', amount: 1500, bank: 'Union **** 5678', requestedDate: '2024-01-17', status: 'pending' },
  { id: 'w9', driver: 'Nilesh Patel', amount: 6000, bank: 'Canara **** 9012', requestedDate: '2024-01-16', status: 'approved' },
  { id: 'w10', driver: 'Suresh Yadav', amount: 9000, bank: 'SBI **** 4321', requestedDate: '2024-01-15', status: 'approved' },
]

export const walletTransactions = [
  { id: 'wt1', user: 'Rahul Sharma', type: 'credit', amount: 500, description: 'Wallet Recharge', date: '2024-01-20 09:00' },
  { id: 'wt2', user: 'Priya Patel', type: 'debit', amount: 185, description: 'Ride R001 payment', date: '2024-01-20 10:30' },
  { id: 'wt3', user: 'Sneha Verma', type: 'credit', amount: 200, description: 'Refund - Ride R003', date: '2024-01-20 11:00' },
  { id: 'wt4', user: 'Karan Mehta', type: 'credit', amount: 1000, description: 'Wallet Recharge', date: '2024-01-19 14:00' },
  { id: 'wt5', user: 'Pooja Singh', type: 'debit', amount: 320, description: 'Ride R002 payment', date: '2024-01-19 11:15' },
  { id: 'wt6', user: 'Divya Nair', type: 'credit', amount: 50, description: 'Referral bonus', date: '2024-01-18 16:00' },
  { id: 'wt7', user: 'Anita Desai', type: 'debit', amount: 450, description: 'Ride R004 payment', date: '2024-01-18 13:30' },
  { id: 'wt8', user: 'Rahul Sharma', type: 'credit', amount: 200, description: 'Wallet Recharge', date: '2024-01-17 10:00' },
]

export const sentNotifications = [
  { id: 'n1', title: 'New Promo! 50% off first ride', target: 'All Riders', sentAt: '2024-01-20 10:00', delivered: 1243 },
  { id: 'n2', title: 'Weekly earnings report ready', target: 'All Drivers', sentAt: '2024-01-20 09:00', delivered: 178 },
  { id: 'n3', title: 'App update available', target: 'All', sentAt: '2024-01-19 18:00', delivered: 1421 },
  { id: 'n4', title: 'Weekend special discount', target: 'All Riders', sentAt: '2024-01-19 08:00', delivered: 1198 },
  { id: 'n5', title: 'Safety guidelines update', target: 'All Drivers', sentAt: '2024-01-18 11:00', delivered: 165 },
  { id: 'n6', title: 'New zone added: IT Hub', target: 'All Drivers', sentAt: '2024-01-17 14:00', delivered: 178 },
  { id: 'n7', title: 'Referral bonus increased to ₹100', target: 'All Riders', sentAt: '2024-01-16 10:00', delivered: 1302 },
  { id: 'n8', title: 'Maintenance window tonight', target: 'All', sentAt: '2024-01-15 20:00', delivered: 1389 },
  { id: 'n9', title: 'Driver verification reminder', target: 'All Drivers', sentAt: '2024-01-14 09:00', delivered: 45 },
  { id: 'n10', title: 'New payment method added', target: 'All Riders', sentAt: '2024-01-13 11:00', delivered: 1421 },
]

export const sosContacts = [
  { id: 's1', name: 'Ahmedabad Police', phone: '100', relation: 'Emergency', addedBy: 'admin' },
  { id: 's2', name: 'Women Helpline', phone: '1091', relation: 'Emergency', addedBy: 'admin' },
  { id: 's3', name: 'Ambulance', phone: '108', relation: 'Emergency', addedBy: 'admin' },
  { id: 's4', name: 'Gora Support 24/7', phone: '+91 99887 00000', relation: 'App Support', addedBy: 'admin' },
  { id: 's5', name: 'Traffic Control', phone: '1095', relation: 'Traffic', addedBy: 'admin' },
]

export const allVehicles = [
  { id: 'v1', number: 'GJ01AB1234', model: 'Maruti Dzire', type: 'Sedan', driver: 'Suresh Yadav', status: 'active' },
  { id: 'v2', number: 'GJ01CD5678', model: 'Bajaj RE Auto', type: 'Auto', driver: 'Mohan Lal', status: 'active' },
  { id: 'v3', number: 'GJ01EF9012', model: 'Mahindra XUV500', type: 'SUV', driver: 'Ramesh Gupta', status: 'pending' },
  { id: 'v4', number: 'GJ02AB3456', model: 'Honda City', type: 'Sedan', driver: 'Dinesh Patil', status: 'active' },
  { id: 'v5', number: 'GJ02CD7890', model: 'Honda Activa', type: 'Bike', driver: 'Harish Tiwari', status: 'blocked' },
  { id: 'v6', number: 'GJ03AB1111', model: 'Maruti Alto', type: 'Mini', driver: 'Prakash Sharma', status: 'active' },
  { id: 'v7', number: 'GJ03CD2222', model: 'Tata Nexon EV', type: 'Electric', driver: 'Nilesh Patel', status: 'pending' },
  { id: 'v8', number: 'GJ04AB3333', model: 'Toyota Etios', type: 'Prime Sedan', driver: 'Sanjay Desai', status: 'active' },
]
