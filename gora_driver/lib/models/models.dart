// All models in one file for simplicity
import '../config/app_config.dart';

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
  final String userProfilePicUrl;
  // Outstation extras — empty for taxi rides
  final String service;       // 'taxi' | 'outstation' | ...
  final String tripType;      // 'one_way' | 'round_trip'
  final String cityFrom;
  final String cityTo;
  final String departureAt;   // ISO string from backend; '' if not scheduled
  final String returnAt;      // ISO string from backend; '' if not round trip
  final int numPassengers;    // 0 if not provided
  // Rental extras
  final int packageHours;
  final int packageKm;
  // Hire extras
  final int hireTotalHours;
  final String transmission;
  // Delivery extras
  final String senderName, senderPhone, receiverName, receiverPhone, itemType;
  final double weightKg;
  final String packageSize;
  final bool isFragile;
  final double codAmount;
  final List<String> parcelPhotos;
  // Multi-stop (in-city A→B→C)
  final List<Map<String, dynamic>> stops;
  // Payment + fare details (numeric, for display)
  final String paymentMode;      // 'cash' | 'wallet' | 'online'
  final num baseFare;            // fare before tip
  final num tipAmount;           // tip added by rider
  final num totalFareValue;      // fare + tip (numeric)
  final num distanceKm;          // trip road distance (km, numeric)
  final num pickupDistanceKm;    // driver → pickup distance (km); 0 if backend omits it
  final int durationMin;         // road duration (min)
  final String routePolyline;    // encoded polyline (pickup→drop)
  // Hire schedule (start/end ISO strings)
  final String hireStartAt, hireEndAt;

  const RideRequestModel({
    required this.id, required this.userName, required this.userPhone, required this.userRating,
    required this.pickupAddress, required this.dropAddress, required this.distance,
    required this.fare, required this.eta, required this.rideType,
    required this.pickupLat, required this.pickupLng, required this.dropLat, required this.dropLng,
    this.userProfilePicUrl = '',
    this.paymentMode = 'cash',
    this.baseFare = 0,
    this.tipAmount = 0,
    this.totalFareValue = 0,
    this.distanceKm = 0,
    this.pickupDistanceKm = 0,
    this.durationMin = 0,
    this.routePolyline = '',
    this.hireStartAt = '',
    this.hireEndAt = '',
    this.service = 'taxi',
    this.tripType = 'one_way',
    this.cityFrom = '',
    this.cityTo = '',
    this.departureAt = '',
    this.returnAt = '',
    this.numPassengers = 0,
    this.packageHours = 0,
    this.packageKm = 0,
    this.hireTotalHours = 0,
    this.transmission = '',
    this.senderName = '', this.senderPhone = '', this.receiverName = '', this.receiverPhone = '', this.itemType = '',
    this.weightKg = 0,
    this.packageSize = '', this.isFragile = false, this.codAmount = 0, this.parcelPhotos = const [],
    this.stops = const [],
  });

  // Build a request model from a pending-request JSON row (backend /rides/driver/pending)
  factory RideRequestModel.fromJson(Map<String, dynamic> r) {
    final num fare = (r['fare'] as num?) ?? 0;
    final num tip = (r['tip'] as num?) ?? 0;
    final num total = (r['totalFare'] as num?) ?? (fare + tip);
    final ratingNum = r['riderRating'];
    final ratingStr = ratingNum is num && ratingNum > 0 ? ratingNum.toStringAsFixed(1) : '5.0';
    final picRaw = (r['riderProfilePicUrl'] ?? '').toString();
    final picUrl = picRaw.isEmpty ? '' : AppConfig.imageUrl(picRaw);
    return RideRequestModel(
      id: r['id']?.toString() ?? '',
      userName: (r['riderName'] ?? 'Rider').toString(),
      userPhone: (r['riderPhone'] ?? '').toString(),
      userRating: ratingStr,
      userProfilePicUrl: picUrl,
      pickupAddress: (r['pickupAddress'] ?? '').toString(),
      dropAddress: (r['dropAddress'] ?? '').toString(),
      distance: '${r['distance'] ?? 0} km',
      fare: '₹ $total',
      eta: '${r['duration'] ?? 4} min',
      rideType: (r['vehicleType'] ?? 'taxi').toString(),
      pickupLat: (r['pickupLat'] ?? 23.0225).toDouble(),
      pickupLng: (r['pickupLng'] ?? 72.5714).toDouble(),
      dropLat: (r['dropLat'] ?? 23.0732).toDouble(),
      dropLng: (r['dropLng'] ?? 72.6208).toDouble(),
      service: (r['service'] ?? 'taxi').toString(),
      tripType: (r['tripType'] ?? 'one_way').toString(),
      cityFrom: (r['cityFrom'] ?? '').toString(),
      cityTo: (r['cityTo'] ?? '').toString(),
      departureAt: (r['departureAt'] ?? '').toString(),
      returnAt: (r['returnAt'] ?? '').toString(),
      numPassengers: (r['numPassengers'] as num?)?.toInt() ?? 0,
      packageHours: (r['packageHours'] as num?)?.toInt() ?? 0,
      packageKm: (r['packageKm'] as num?)?.toInt() ?? 0,
      hireTotalHours: (r['hireTotalHours'] as num?)?.toInt() ?? 0,
      transmission: (r['transmission'] ?? '').toString(),
      senderName: (r['senderName'] ?? '').toString(), senderPhone: (r['senderPhone'] ?? '').toString(),
      receiverName: (r['receiverName'] ?? '').toString(), receiverPhone: (r['receiverPhone'] ?? '').toString(),
      itemType: (r['itemType'] ?? '').toString(), weightKg: (r['weightKg'] as num?)?.toDouble() ?? 0,
      packageSize: (r['packageSize'] ?? '').toString(), isFragile: (r['isFragile'] as bool?) ?? false,
      codAmount: (r['codAmount'] as num?)?.toDouble() ?? 0,
      parcelPhotos: ((r['parcelPhotos'] as List?) ?? []).map((e) => e.toString()).toList(),
      stops: ((r['stops'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      paymentMode: (r['paymentMode'] ?? 'cash').toString(),
      baseFare: fare,
      tipAmount: tip,
      totalFareValue: total,
      distanceKm: (r['distance'] as num?) ?? 0,
      pickupDistanceKm: (r['pickupDistance'] as num?) ?? 0,
      durationMin: (r['duration'] as num?)?.toInt() ?? 0,
      routePolyline: (r['routePolyline'] ?? '').toString(),
      hireStartAt: (r['hireStartAt'] ?? '').toString(),
      hireEndAt: (r['hireEndAt'] ?? '').toString(),
    );
  }
}

class TripModel {
  final String id, userName, pickupAddress, dropAddress, distance, fare, date, status, paymentMode, duration;
  final double rating;
  // Service info — taxi / outstation / rental / hire_driver
  final String service;
  final String vehicleType;
  final String tripType;
  final String cityFrom;
  final String cityTo;
  final int numPassengers;

  const TripModel({
    required this.id, required this.userName, required this.pickupAddress, required this.dropAddress,
    required this.distance, required this.fare, required this.date, required this.status,
    required this.paymentMode, required this.duration, required this.rating,
    this.service = 'taxi',
    this.vehicleType = '',
    this.tripType = 'one_way',
    this.cityFrom = '',
    this.cityTo = '',
    this.numPassengers = 0,
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
