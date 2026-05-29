import '../models/models.dart';

// Simulates network delay
Future<T> mockFetch<T>(T data, {int ms = 800}) async {
  await Future.delayed(Duration(milliseconds: ms));
  return data;
}

// ─── DRIVER ─────────────────────────────────────────
const mockDriver = DriverModel(
  id: 'DRV001',
  name: 'Rajesh Kumar',
  phone: '+91 98765 43210',
  email: 'rajesh.kumar@goradriver.com',
  profilePic: '',
  vehicleNumber: 'GJ01 AB 1234',
  vehicleModel: 'Maruti Swift Dzire',
  vehicleType: 'Sedan',
  rating: '4.8',
  totalRides: '1,245',
  status: 'approved',
  walletBalance: 2450.75,
  isOnline: false,
  isApproved: true,
);

// ─── RIDE REQUESTS ───────────────────────────────────
const mockRideRequests = [
  RideRequestModel(
    id: 'R1001', userName: 'Priya Sharma', userPhone: '+91 87654 32109',
    userRating: '4.6', pickupAddress: 'Ahmedabad Railway Station, Kalupur',
    dropAddress: 'Sardar Patel International Airport', distance: '12.4 km',
    fare: '₹ 185', eta: '4 mins', rideType: 'taxi',
    pickupLat: 23.0225, pickupLng: 72.5714, dropLat: 23.0732, dropLng: 72.6208,
  ),
  RideRequestModel(
    id: 'R1002', userName: 'Amit Patel', userPhone: '+91 76543 21098',
    userRating: '4.9', pickupAddress: 'Iscon Cross Roads, SG Highway',
    dropAddress: 'Maninagar Bus Stand', distance: '8.2 km',
    fare: '₹ 120', eta: '6 mins', rideType: 'taxi',
    pickupLat: 23.0420, pickupLng: 72.5060, dropLat: 22.9940, dropLng: 72.6031,
  ),
];

// ─── TRIP HISTORY ────────────────────────────────────
const mockTrips = [
  TripModel(id: 'T2001', userName: 'Priya Sharma', pickupAddress: 'Ahmedabad Railway Station', dropAddress: 'SG Highway', distance: '12.4 km', fare: '₹ 185', date: 'Today, 10:30 AM', status: 'completed', paymentMode: 'Cash', duration: '28 min', rating: 5.0),
  TripModel(id: 'T2002', userName: 'Rahul Shah', pickupAddress: 'Bopal Crossroads', dropAddress: 'GIFT City', distance: '15.1 km', fare: '₹ 220', date: 'Today, 08:15 AM', status: 'completed', paymentMode: 'Online', duration: '35 min', rating: 4.0),
  TripModel(id: 'T2003', userName: 'Meera Joshi', pickupAddress: 'Prahlad Nagar Garden', dropAddress: 'Navrangpura', distance: '5.8 km', fare: '₹ 95', date: 'Yesterday, 07:40 PM', status: 'completed', paymentMode: 'Cash', duration: '18 min', rating: 5.0),
  TripModel(id: 'T2004', userName: 'Karan Mehta', pickupAddress: 'Thaltej Metro', dropAddress: 'Maninagar', distance: '18.3 km', fare: '₹ 270', date: 'Yesterday, 03:22 PM', status: 'completed', paymentMode: 'Online', duration: '42 min', rating: 4.0),
  TripModel(id: 'T2005', userName: 'Nisha Patel', pickupAddress: 'Science City', dropAddress: 'CG Road', distance: '9.6 km', fare: '₹ 145', date: '25 May, 11:10 AM', status: 'cancelled', paymentMode: 'Cash', duration: '0 min', rating: 0.0),
  TripModel(id: 'T2006', userName: 'Suresh Verma', pickupAddress: 'Sabarmati Riverfront', dropAddress: 'ISRO Colony', distance: '11.2 km', fare: '₹ 165', date: '24 May, 09:05 AM', status: 'completed', paymentMode: 'Online', duration: '26 min', rating: 5.0),
  TripModel(id: 'T2007', userName: 'Anita Desai', pickupAddress: 'Vastrapur Lake', dropAddress: 'Satellite Road', distance: '3.4 km', fare: '₹ 65', date: '23 May, 06:30 PM', status: 'completed', paymentMode: 'Cash', duration: '12 min', rating: 4.0),
  TripModel(id: 'T2008', userName: 'Deepak Singh', pickupAddress: 'Law Garden', dropAddress: 'Gota', distance: '14.7 km', fare: '₹ 215', date: '22 May, 01:15 PM', status: 'completed', paymentMode: 'Online', duration: '38 min', rating: 5.0),
];

// ─── EARNINGS ───────────────────────────────────────
const mockEarnings = [
  EarningsModel(date: 'Mon', amount: '820', rides: '6', distance: '68 km', duration: '3h 20m'),
  EarningsModel(date: 'Tue', amount: '1140', rides: '9', distance: '94 km', duration: '4h 45m'),
  EarningsModel(date: 'Wed', amount: '650', rides: '5', distance: '52 km', duration: '2h 55m'),
  EarningsModel(date: 'Thu', amount: '980', rides: '7', distance: '81 km', duration: '4h 00m'),
  EarningsModel(date: 'Fri', amount: '1350', rides: '11', distance: '112 km', duration: '5h 30m'),
  EarningsModel(date: 'Sat', amount: '1680', rides: '13', distance: '138 km', duration: '6h 15m'),
  EarningsModel(date: 'Sun', amount: '1220', rides: '10', distance: '102 km', duration: '5h 05m'),
];

// ─── WALLET ──────────────────────────────────────────
const mockTransactions = [
  WalletTransaction(id: 'W001', type: 'Trip Earning', description: 'Trip #T2001 • Priya Sharma', amount: '+ ₹ 185', date: 'Today 10:58 AM', isCredit: true),
  WalletTransaction(id: 'W002', type: 'Trip Earning', description: 'Trip #T2002 • Rahul Shah', amount: '+ ₹ 220', date: 'Today 08:50 AM', isCredit: true),
  WalletTransaction(id: 'W003', type: 'Withdrawal', description: 'Bank Transfer', amount: '- ₹ 1000', date: 'Yesterday 06:00 PM', isCredit: false),
  WalletTransaction(id: 'W004', type: 'Trip Earning', description: 'Trip #T2003 • Meera Joshi', amount: '+ ₹ 95', date: 'Yesterday 07:58 PM', isCredit: true),
  WalletTransaction(id: 'W005', type: 'Incentive', description: 'Weekend Bonus', amount: '+ ₹ 250', date: '25 May 11:00 PM', isCredit: true),
  WalletTransaction(id: 'W006', type: 'Trip Earning', description: 'Trip #T2006 • Suresh Verma', amount: '+ ₹ 165', date: '24 May 09:31 AM', isCredit: true),
  WalletTransaction(id: 'W007', type: 'Deduction', description: 'Commission Deduction', amount: '- ₹ 125', date: '24 May 12:00 AM', isCredit: false),
];

// ─── NOTIFICATIONS ───────────────────────────────────
const mockNotifications = [
  NotificationModel(id: 'N001', title: 'New Ride Request!', body: 'Priya Sharma is requesting a ride from Ahmedabad Station.', time: '2 min ago', type: 'ride', isRead: false),
  NotificationModel(id: 'N002', title: 'Payment Received', body: 'You received ₹185 for Trip #T2001.', time: '1 hr ago', type: 'payment', isRead: false),
  NotificationModel(id: 'N003', title: 'Weekend Bonus 🎉', body: 'Complete 10 rides this weekend and earn ₹500 bonus!', time: '3 hr ago', type: 'incentive', isRead: true),
  NotificationModel(id: 'N004', title: 'Document Expiry', body: 'Your RC document expires in 30 days. Please update.', time: 'Yesterday', type: 'document', isRead: true),
  NotificationModel(id: 'N005', title: 'Rating Update', body: 'Great job! Your rating improved to 4.8 ⭐', time: '2 days ago', type: 'rating', isRead: true),
];

// ─── LEADERBOARD ─────────────────────────────────────
const mockLeaderboard = [
  LeaderboardEntry(rank: 1, name: 'Suresh Patel', rides: '142', earnings: '₹ 18,450', badge: '🥇', isMe: false),
  LeaderboardEntry(rank: 2, name: 'Mohan Verma', rides: '138', earnings: '₹ 17,820', badge: '🥈', isMe: false),
  LeaderboardEntry(rank: 3, name: 'Rajesh Kumar', rides: '134', earnings: '₹ 17,290', badge: '🥉', isMe: true),
  LeaderboardEntry(rank: 4, name: 'Dinesh Shah', rides: '128', earnings: '₹ 16,500', badge: '', isMe: false),
  LeaderboardEntry(rank: 5, name: 'Kiran Desai', rides: '121', earnings: '₹ 15,640', badge: '', isMe: false),
  LeaderboardEntry(rank: 6, name: 'Amit Rao', rides: '118', earnings: '₹ 15,100', badge: '', isMe: false),
  LeaderboardEntry(rank: 7, name: 'Vikas Joshi', rides: '112', earnings: '₹ 14,350', badge: '', isMe: false),
  LeaderboardEntry(rank: 8, name: 'Prakash Nair', rides: '108', earnings: '₹ 13,900', badge: '', isMe: false),
];

// ─── INCENTIVES ──────────────────────────────────────
const mockIncentives = [
  IncentiveModel(title: 'Morning Star', description: 'Complete 5 rides between 6AM–10AM', target: '5', current: '3', reward: '₹ 150 Bonus', deadline: 'Today', progress: 0.6),
  IncentiveModel(title: 'Weekend Warrior', description: 'Complete 20 rides this weekend', target: '20', current: '13', reward: '₹ 500 Bonus', deadline: 'Sun, 27 May', progress: 0.65),
  IncentiveModel(title: 'Top Performer', description: 'Maintain 4.7+ rating for 50 rides', target: '50', current: '42', reward: '₹ 1000 Bonus', deadline: '31 May', progress: 0.84),
];

// ─── SOS ─────────────────────────────────────────────
const mockSOSContacts = [
  SOSContact(name: 'Sunita Kumar', phone: '+91 98765 11111', relation: 'Wife'),
  SOSContact(name: 'Ravi Kumar', phone: '+91 98765 22222', relation: 'Brother'),
];

// ─── DOCUMENTS ───────────────────────────────────────
const mockDocuments = [
  DocumentModel(name: 'Driving License', status: 'approved', expiryDate: '15 Aug 2027'),
  DocumentModel(name: 'Registration Certificate (RC)', status: 'approved', expiryDate: '30 May 2024'),
  DocumentModel(name: 'Insurance Certificate', status: 'approved', expiryDate: '12 Jan 2025'),
  DocumentModel(name: 'Permit', status: 'pending', expiryDate: 'N/A'),
  DocumentModel(name: 'Profile Photo', status: 'approved', expiryDate: 'N/A'),
];

// ─── SUPPORT TICKETS ─────────────────────────────────
const mockTickets = [
  SupportTicket(id: 'TKT001', subject: 'Payment not received for trip T2005', status: 'open', date: '26 May 2025', lastMessage: 'Please check your wallet balance.'),
  SupportTicket(id: 'TKT002', subject: 'App crashing on Android 13', status: 'resolved', date: '20 May 2025', lastMessage: 'Issue resolved in latest update.'),
];

// ─── MOCK SERVICES ───────────────────────────────────
class MockAuthService {
  static Future<bool> login(String phone) => mockFetch(true);
  static Future<bool> verifyOtp(String otp) => mockFetch(otp == '1234');
  static Future<DriverModel> getProfile() => mockFetch(mockDriver);
}

class MockRideService {
  static Future<RideRequestModel> getIncomingRide() => mockFetch(mockRideRequests[0], ms: 2000);
  static Future<bool> acceptRide(String id) => mockFetch(true);
  static Future<bool> rejectRide(String id) => mockFetch(true);
  static Future<bool> arrivedAtPickup(String id) => mockFetch(true);
  static Future<bool> startRide(String id) => mockFetch(true);
  static Future<bool> endRide(String id) => mockFetch(true);
}

class MockHistoryService {
  static Future<List<TripModel>> getHistory() => mockFetch(mockTrips);
  static Future<TripModel> getTripDetail(String id) => mockFetch(mockTrips.firstWhere((t) => t.id == id));
}

class MockEarningsService {
  static Future<List<EarningsModel>> getWeeklyEarnings() => mockFetch(mockEarnings);
  static Future<Map<String, String>> getSummary() => mockFetch({
    'today': '₹ 405', 'week': '₹ 7,840', 'month': '₹ 28,350',
    'totalRides': '52', 'totalDistance': '647 km',
  });
}

class MockWalletService {
  static Future<double> getBalance() => mockFetch(2450.75);
  static Future<List<WalletTransaction>> getTransactions() => mockFetch(mockTransactions);
  static Future<bool> withdraw(double amount) => mockFetch(true);
}

class MockNotificationService {
  static Future<List<NotificationModel>> getAll() => mockFetch(mockNotifications);
}
