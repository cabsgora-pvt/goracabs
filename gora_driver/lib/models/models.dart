// All models in one file for simplicity

class DriverModel {
  final String id, name, phone, email, profilePic, vehicleNumber, vehicleModel, vehicleType, rating, totalRides, status;
  final double walletBalance;
  final bool isOnline, isApproved;

  const DriverModel({
    required this.id, required this.name, required this.phone, required this.email,
    required this.profilePic, required this.vehicleNumber, required this.vehicleModel,
    required this.vehicleType, required this.rating, required this.totalRides,
    required this.status, required this.walletBalance, required this.isOnline, required this.isApproved,
  });
}

class RideRequestModel {
  final String id, userName, userPhone, userRating, pickupAddress, dropAddress, distance, fare, eta, rideType;
  final double pickupLat, pickupLng, dropLat, dropLng;

  const RideRequestModel({
    required this.id, required this.userName, required this.userPhone, required this.userRating,
    required this.pickupAddress, required this.dropAddress, required this.distance,
    required this.fare, required this.eta, required this.rideType,
    required this.pickupLat, required this.pickupLng, required this.dropLat, required this.dropLng,
  });
}

class TripModel {
  final String id, userName, pickupAddress, dropAddress, distance, fare, date, status, paymentMode, duration;
  final double rating;

  const TripModel({
    required this.id, required this.userName, required this.pickupAddress, required this.dropAddress,
    required this.distance, required this.fare, required this.date, required this.status,
    required this.paymentMode, required this.duration, required this.rating,
  });
}

class EarningsModel {
  final String date, amount, rides, distance, duration;
  const EarningsModel({required this.date, required this.amount, required this.rides, required this.distance, required this.duration});
}

class WalletTransaction {
  final String id, type, description, amount, date;
  final bool isCredit;
  const WalletTransaction({required this.id, required this.type, required this.description, required this.amount, required this.date, required this.isCredit});
}

class NotificationModel {
  final String id, title, body, time, type;
  final bool isRead;
  const NotificationModel({required this.id, required this.title, required this.body, required this.time, required this.type, required this.isRead});
}

class LeaderboardEntry {
  final int rank;
  final String name, rides, earnings, badge;
  final bool isMe;
  const LeaderboardEntry({required this.rank, required this.name, required this.rides, required this.earnings, required this.badge, required this.isMe});
}

class IncentiveModel {
  final String title, description, target, current, reward, deadline;
  final double progress;
  const IncentiveModel({required this.title, required this.description, required this.target, required this.current, required this.reward, required this.deadline, required this.progress});
}

class SOSContact {
  final String name, phone, relation;
  const SOSContact({required this.name, required this.phone, required this.relation});
}

class DocumentModel {
  final String name, status, expiryDate;
  const DocumentModel({required this.name, required this.status, required this.expiryDate});
}

class SupportTicket {
  final String id, subject, status, date, lastMessage;
  const SupportTicket({required this.id, required this.subject, required this.status, required this.date, required this.lastMessage});
}
