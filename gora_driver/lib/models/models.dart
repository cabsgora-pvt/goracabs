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

  // Shared shape of the `driver` map returned by GET /auth/driver/profile and
  // POST /auth/driver/verify-otp — kept in one place so the two call sites
  // (session check, home load) can't drift apart.
  factory DriverModel.fromApi(Map<String, dynamic> d) => DriverModel(
    id: d['_id'] as String? ?? '',
    name: d['name'] as String? ?? '',
    phone: d['phone'] as String? ?? '',
    email: d['email'] as String? ?? '',
    profilePic: d['profilePicUrl'] as String? ?? '',
    vehicleNumber: d['vehicleRegistrationNumber'] as String? ?? d['vehicleNumber'] as String? ?? '',
    vehicleModel: d['vehicleModel'] as String? ?? '',
    vehicleType: d['selectedVehicleTypeName'] as String? ?? d['vehicleType'] as String? ?? '',
    rating: d['rating']?.toString() ?? '0',
    totalRides: d['totalRides']?.toString() ?? '0',
    status: d['status'] as String? ?? 'pending',
    walletBalance: (d['walletBalance'] as num?)?.toDouble() ?? 0.0,
    isOnline: d['isOnline'] as bool? ?? false,
    isApproved: (d['status'] as String?) == 'approved',
  );
}

class RideRequestModel {
  final String id, userName, userPhone, userRating, pickupAddress, dropAddress, distance, fare, eta, rideType;
  final double pickupLat, pickupLng, dropLat, dropLng;
  final String userProfilePicUrl;
  // When this request was offered exclusively to this driver, the moment that
  // offer lapses. The request card counts down to THIS instead of a hardcoded
  // guess, so the ring can no longer expire while the server still holds the
  // offer open (or linger after it has moved on).
  final DateTime? offerExpiresAt;
  /// Server-side ride status ('accepted' | 'arrived' | 'ongoing' | ...). Empty for
  /// a request not yet accepted. Lets a resumed screen start at the right step
  /// instead of always at "arrive".
  final String status;
  /// Server-computed seconds the driver has already waited at pickup, or null
  /// when not waiting. Seeds the resumed waiting timer without trusting the
  /// phone's clock.
  final int? waitingSec;
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
  /// Where an in-progress job had got to, as the server last saw it. Default
  /// (nothing started) for a request that has not begun.
  final RideProgress progress;

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
    this.offerExpiresAt,
    this.status = '',
    this.waitingSec,
    this.packageHours = 0,
    this.packageKm = 0,
    this.hireTotalHours = 0,
    this.transmission = '',
    this.senderName = '', this.senderPhone = '', this.receiverName = '', this.receiverPhone = '', this.itemType = '',
    this.weightKg = 0,
    this.packageSize = '', this.isFragile = false, this.codAmount = 0, this.parcelPhotos = const [],
    this.stops = const [],
    this.progress = const RideProgress(),
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
      // Arrival ETA = this driver → pickup (server-computed, ETA-ranked feed).
      // This used to show r['duration'], which is the pickup→drop TRIP time,
      // with a made-up default of 4 min.
      eta: r['pickupEtaMin'] != null ? '${r['pickupEtaMin']} min' : '—',
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
      offerExpiresAt: DateTime.tryParse((r['offerExpiresAt'] ?? '').toString())?.toLocal(),
      status: (r['status'] ?? '').toString(),
      waitingSec: (r['waitingSec'] as num?)?.toInt(),
      durationMin: (r['duration'] as num?)?.toInt() ?? 0,
      routePolyline: (r['routePolyline'] ?? '').toString(),
      hireStartAt: (r['hireStartAt'] ?? '').toString(),
      hireEndAt: (r['hireEndAt'] ?? '').toString(),
      progress: RideProgress.fromJson(r),
    );
  }
}

/// How far an in-progress job had got, from /rides/driver/active.
///
/// A reopened ride screen knew none of this and started every job over: a
/// rental's clock read 0:00, a parcel already on its way asked to be collected
/// again, a round trip at its destination asked for "arrived at destination"
/// a second time, and a multi-stop ride went back to stop 1. Every field
/// defaults to "not started", which is also what an older backend that does not
/// send them yields — so a screen given one behaves exactly as it did before.
class RideProgress {
  /// Server-clock seconds since the rental began; null until it has.
  final int? rentalElapsedSec;
  final String rentalPhase;
  final bool rentalWaiting;
  final double actualKm;
  final List<Map<String, dynamic>> rentalStops;

  /// Server-clock seconds since the hire began; null until it has.
  final int? hireElapsedSec;
  final String hirePhase;

  /// 'pending' | 'in_transit' | 'collected' | 'delivered' | 'returned'.
  final String deliveryPhase;

  /// Round-trip outstation leg: 'at_destination' | 'returning', else ''.
  final String outstationPhase;
  final bool nightHaltConfirmed;

  final int currentStopIndex;
  final bool waitingAtStop;

  /// The driver has ended the job and the rider has not paid online yet.
  final bool awaitingPayment;

  /// Tolls entered so far on an outstation trip, and their total.
  final List<TollEntry> tolls;
  final num tollCharge;

  const RideProgress({
    this.rentalElapsedSec,
    this.rentalPhase = '',
    this.rentalWaiting = false,
    this.actualKm = 0,
    this.rentalStops = const [],
    this.hireElapsedSec,
    this.hirePhase = '',
    this.deliveryPhase = '',
    this.outstationPhase = '',
    this.nightHaltConfirmed = false,
    this.currentStopIndex = 0,
    this.waitingAtStop = false,
    this.awaitingPayment = false,
    this.tolls = const [],
    this.tollCharge = 0,
  });

  bool get rentalStarted => rentalElapsedSec != null;
  bool get hireStarted => hireElapsedSec != null;
  /// The parcel is with the driver, on its way to the receiver.
  bool get parcelCollected => deliveryPhase == 'in_transit' || deliveryPhase == 'collected';

  factory RideProgress.fromJson(Map<String, dynamic> r) {
    int? secs(dynamic v) => v is num ? v.toInt() : null;
    final leg = (r['outstationPhase'] ?? '').toString();
    return RideProgress(
      rentalElapsedSec: secs(r['rentalElapsedSec']),
      rentalPhase: (r['rentalPhase'] ?? '').toString(),
      rentalWaiting: r['isWaiting'] == true,
      actualKm: (r['actualKm'] as num?)?.toDouble() ?? 0,
      rentalStops: ((r['rentalStops'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
      hireElapsedSec: secs(r['hireElapsedSec']),
      hirePhase: (r['hirePhase'] ?? '').toString(),
      deliveryPhase: (r['deliveryPhase'] ?? '').toString(),
      // The server's model defaults this to 'pickup_pending'; only the two legs
      // the driver screen acts on mean anything to it.
      outstationPhase: (leg == 'at_destination' || leg == 'returning') ? leg : '',
      nightHaltConfirmed: r['nightHaltConfirmed'] == true,
      currentStopIndex: (r['currentStopIndex'] as num?)?.toInt() ?? 0,
      waitingAtStop: r['isWaitingAtStop'] == true,
      awaitingPayment: r['awaitingPayment'] == true,
      tolls: TollEntry.listFrom(r['tolls']),
      tollCharge: (r['tollCharge'] as num?) ?? 0,
    );
  }
}

/// One toll the driver paid on an outstation trip, as the server holds it.
class TollEntry {
  final String id;
  final num amount;
  final DateTime? at;
  /// 'prompt' when added from the toll-road prompt, else 'manual'.
  final String source;
  /// Where it was paid, as an address; '' when unknown.
  final String place;
  /// The rider has reported this toll to support.
  final bool reported;
  const TollEntry({required this.id, required this.amount, this.at, this.source = 'manual',
      this.place = '', this.reported = false});

  factory TollEntry.fromJson(Map<String, dynamic> j) => TollEntry(
    id: (j['id'] ?? j['_id'] ?? '').toString(),
    amount: (j['amount'] as num?) ?? 0,
    at: DateTime.tryParse((j['at'] ?? '').toString())?.toLocal(),
    source: (j['source'] ?? 'manual').toString(),
    place: (j['place'] ?? '').toString(),
    reported: j['reported'] == true,
  );

  static List<TollEntry> listFrom(dynamic v) => (v is List ? v : const [])
      .whereType<Map>()
      .map((e) => TollEntry.fromJson(Map<String, dynamic>.from(e)))
      .where((t) => t.id.isNotEmpty && t.amount > 0)
      .toList();

  static num total(List<TollEntry> tolls) => tolls.fold<num>(0, (s, t) => s + t.amount);
}

class TripModel {
  final String id, userName, pickupAddress, dropAddress, distance, fare, date, status, paymentMode, duration;
  final String userProfilePicUrl;
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
    this.userProfilePicUrl = '',
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
