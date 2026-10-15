import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

class DriverApiService {
  static String get baseUrl => AppConfig.apiBaseUrl;

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('driver_token');
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('driver_token', token);
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('driver_token');
  }

  /// Decodes an API response without ever throwing.
  ///
  /// Every call site used to do a bare `jsonDecode(res.body) as Map`, which
  /// throws whenever the body is not a JSON object — and in the real world that
  /// is common: an nginx 502 returns HTML, a 204 returns nothing, and hotel or
  /// airport wifi captive portals return a login page for every request. The
  /// FormatException then propagated out of whatever screen made the call.
  ///
  /// Callers already check `res['error']`, so failures are reported that way
  /// instead of thrown.
  static Map<String, dynamic> _decode(http.Response res) {
    final body = res.body;
    if (body.trim().isEmpty) {
      return {'error': 'No response from server (HTTP ${res.statusCode})'};
    }
    try {
      final v = jsonDecode(body);
      if (v is Map<String, dynamic>) return v;
      return {'error': 'Unexpected response from server'};
    } catch (_) {
      return {
        'error': res.statusCode >= 500
            ? 'Server error (${res.statusCode}). Please try again.'
            : 'Could not read the server response. Check your connection.',
      };
    }
  }

  static Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body, {bool auth = false}) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (auth) {
      final token = await getToken();
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    final res = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: headers,
      body: jsonEncode(body),
    );
    return _decode(res);
  }

  static Future<Map<String, dynamic>> delete(String path) async {
    final token = await getToken();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    final res = await http.delete(Uri.parse('$baseUrl$path'), headers: headers);
    return _decode(res);
  }

  static Future<Map<String, dynamic>> get(String path) async {
    final token = await getToken();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    final res = await http.get(Uri.parse('$baseUrl$path'), headers: headers);
    return _decode(res);
  }

  static Future<String?> uploadFile(XFile file) async {
    final bytes = await file.readAsBytes();
    final uri = Uri.parse('$baseUrl/upload');
    final request = http.MultipartRequest('POST', uri);
    // /api/upload now requires a signed-in caller — without this header every
    // document, proof-of-delivery photo and signature upload 401s.
    final token = await getToken();
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: file.name.isNotEmpty ? file.name : 'doc.jpg',
    ));
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    if (data['url'] != null) return AppConfig.imageUrl(data['url'] as String);
    return null;
  }

  // Upload raw bytes (used for signature PNG) → returns full url
  static Future<String?> uploadBytes(Uint8List bytes, String filename) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/upload'));
      final token = await getToken();
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
      final res = await http.Response.fromStream(await request.send());
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['url'] != null) return AppConfig.imageUrl(data['url'] as String);
      return null;
    } catch (_) { return null; }
  }

  // Auth
  static Future<Map<String, dynamic>> sendOtp(String phone) =>
      post('/auth/driver/send-otp', {'phone': phone});

  static Future<Map<String, dynamic>> verifyOtp(String phone, String otp) =>
      post('/auth/driver/verify-otp', {'phone': phone, 'otp': otp});

  static Future<Map<String, dynamic>> getProfile() => get('/auth/driver/profile');

  // Real notification feed for this driver (broadcasts + anything addressed to
  // them). The notifications screen used to be served by MockNotificationService.
  static Future<Map<String, dynamic>> getNotifications() =>
      get('/auth/driver/notifications');

  // Registration steps
  static Future<Map<String, dynamic>> savePersonal(Map<String, dynamic> data) =>
      post('/auth/driver/register/personal', data, auth: true);

  static Future<Map<String, dynamic>> saveVehicle(Map<String, dynamic> data) =>
      post('/auth/driver/register/vehicle', data, auth: true);

  static Future<Map<String, dynamic>> saveDocuments(List<Map<String, dynamic>> docs) =>
      post('/auth/driver/register/documents', {'documents': docs}, auth: true);

  static Future<Map<String, dynamic>> saveBank(Map<String, dynamic> data) =>
      post('/auth/driver/register/bank', data, auth: true);

  // Register the device's FCM push token so the backend can wake the app with a
  // ride alert even when it's fully closed (Layer 2 — needs Firebase configured).
  static Future<Map<String, dynamic>> saveFcmToken(String token) =>
      post('/auth/driver/fcm-token', {'token': token}, auth: true);

  // Update driver preferences (currently: acceptsOutstation). Uses POST since CORS
  // allow-methods always includes POST. Returns the saved values.
  static Future<Map<String, dynamic>> updatePreferences(Map<String, dynamic> prefs) =>
      post('/auth/driver/preferences', prefs, auth: true);

  // Zones
  static Future<List<Map<String, dynamic>>> getZones() async {
    final res = await get('/zones');
    final zones = res['zones'] as List? ?? [];
    return zones.map((z) => Map<String, dynamic>.from(z as Map)).toList();
  }

  // Vehicle types
  static Future<List<Map<String, dynamic>>> getVehicleTypes() async {
    final res = await get('/vehicles/types');
    final types = res['types'] as List? ?? [];
    return types.map((t) => Map<String, dynamic>.from(t as Map)).toList();
  }

  // ── Online + location ─────────────────────────────────────
  static Future<Map<String, dynamic>> setOnline(bool isOnline, double lat, double lng) =>
      post('/auth/driver/online', {'isOnline': isOnline, 'lat': lat, 'lng': lng}, auth: true);

  static Future<Map<String, dynamic>> updateLocation(double lat, double lng) =>
      post('/auth/driver/location', {'lat': lat, 'lng': lng}, auth: true);

  // Road route + traffic-aware ETA for the current navigation leg.
  // Returns { polyline, distanceKm, durationMin } (durationMin uses
  // duration_in_traffic when Google provides it).
  // `steps: true` also returns turn-by-turn manoeuvres, which power the in-app
  // navigation banner. `waypoints` lets one call cover a multi-stop chain.
  static Future<Map<String, dynamic>> getDirections({
    required double originLat, required double originLng,
    required double destLat, required double destLng,
    bool steps = false,
    List<List<double>>? waypoints,
    /// Language of the step instructions ('en' | 'hi'); null leaves Google's default.
    String? language,
  }) {
    final wp = (waypoints == null || waypoints.isEmpty)
        ? ''
        : '&waypoints=${Uri.encodeComponent(waypoints.map((p) => '${p[0]},${p[1]}').join('|'))}';
    return get('/directions?originLat=$originLat&originLng=$originLng'
        '&destLat=$destLat&destLng=$destLng${steps ? '&steps=1' : ''}$wp'
        '${language != null ? '&language=$language' : ''}');
  }

  // ── Ride flow ─────────────────────────────────────────────
  static Future<Map<String, dynamic>> getPendingRequests() =>
      get('/rides/driver/pending');

  // Returns the parsed body plus an injected '_status' http code so callers can detect 409 (taken)
  static Future<Map<String, dynamic>> acceptRide(String id) async {
    final token = await getToken();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    final res = await http.post(
      Uri.parse('$baseUrl/rides/$id/accept'),
      headers: headers,
      body: jsonEncode({}),
    );
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    data['_status'] = res.statusCode;
    return data;
  }

  static Future<Map<String, dynamic>> rejectRide(String id) =>
      post('/rides/$id/reject', {}, auth: true);

  static Future<Map<String, dynamic>> arrivedRide(String id) =>
      post('/rides/$id/arrived', {}, auth: true);

  static Future<Map<String, dynamic>> startRide(String id, String otp) =>
      post('/rides/$id/start', {'otp': otp}, auth: true);

  static Future<Map<String, dynamic>> completeRide(String id) =>
      post('/rides/$id/complete', {}, auth: true);

  // Online ride: driver asks the rider to pay before the ride completes.
  static Future<Map<String, dynamic>> requestPayment(String id) =>
      post('/rides/$id/request-payment', {}, auth: true);

  // The driver's current in-progress ride (to resume the ride screen on reopen).
  static Future<Map<String, dynamic>> getActiveRide() => get('/rides/driver/active');

  // Incentives with this driver's real progress (server-computed from rides).
  static Future<Map<String, dynamic>> getIncentives() =>
      get('/auth/driver/incentives');

  // Emergency contacts: admin-provided control-room numbers + the driver's own.
  static Future<Map<String, dynamic>> getSosContacts() =>
      get('/auth/driver/sos-contacts');

  static Future<Map<String, dynamic>> addSosContact(Map<String, dynamic> body) =>
      post('/auth/driver/sos-contacts', body, auth: true);

  static Future<Map<String, dynamic>> deleteSosContact(String id) =>
      delete('/auth/driver/sos-contacts/$id');

  // SOS alert (raised when the driver taps SOS)
  static Future<Map<String, dynamic>> sendSosAlert(Map<String, dynamic> body) =>
      post('/support/sos-alert', body, auth: true);

  // In-ride chat (driver ↔ rider)
  static Future<Map<String, dynamic>> getRideMessages(String rideId) =>
      get('/rides/$rideId/messages');
  static Future<Map<String, dynamic>> sendRideMessage(String rideId, String text) =>
      post('/rides/$rideId/messages', {'sender': 'driver', 'text': text}, auth: true);

  static Future<Map<String, dynamic>> getRide(String id) => get('/rides/$id');

  static Future<Map<String, dynamic>> rateRide(String id, int rating, String review) =>
      post('/rides/$id/rate', {'by': 'driver', 'rating': rating, 'review': review}, auth: true);

  static Future<Map<String, dynamic>> getTripHistory() =>
      get('/rides/driver/history');

  // Today/week earnings summary for the home dashboard
  static Future<Map<String, dynamic>> getEarningsSummary() =>
      get('/rides/driver/summary');

  // Earnings page: 7-day daily breakdown ending at [date] (default today) + summary
  static Future<Map<String, dynamic>> getEarnings({DateTime? date}) {
    var path = '/rides/driver/earnings';
    if (date != null) {
      final d = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      path += '?date=$d';
    }
    return get(path);
  }

  // ── Subscription (membership) ─────────────────────────────
  // { current, history, plans, walletBalance }
  static Future<Map<String, dynamic>> getSubscription() =>
      get('/auth/driver/subscription');

  // Public payment config (razorpay enabled + keyId + mode)
  static Future<Map<String, dynamic>> getPaymentConfig() => get('/payment/config');

  // Public driver-app config (per-service ringtones + wallet rules)
  static Future<Map<String, dynamic>> getDriverConfig() => get('/driver-config');

  // Driver wallet: { balance, transactions }
  static Future<Map<String, dynamic>> getWallet() => get('/auth/driver/wallet');

  // Referral: { code, referrerReward, refereeReward, referredCount, referralEarnings }
  static Future<Map<String, dynamic>> getReferral() => get('/auth/driver/referral');

  // Save the driver's payment QR image url
  static Future<Map<String, dynamic>> savePaymentQr(String qrUrl) =>
      post('/auth/driver/qr', {'qrUrl': qrUrl}, auth: true);

  // Zone leaderboard: { zone, entries: [{rank,name,rides,earnings,isMe}] }
  static Future<Map<String, dynamic>> getLeaderboard() => get('/rides/driver/leaderboard');

  // Rate card for the driver's zone: { zone, cards: [{vehicleType,baseFare,perKm,perMin,minFare}] }
  static Future<Map<String, dynamic>> getRateCard() => get('/auth/driver/ratecard');

  // ── Support tickets ───────────────────────────────────────
  static Future<Map<String, dynamic>> getSupportTickets() => get('/auth/driver/support/tickets');
  static Future<Map<String, dynamic>> createSupportTicket(String subject, String message, {String category = 'general'}) =>
      post('/auth/driver/support/tickets', {'subject': subject, 'message': message, 'category': category}, auth: true);
  static Future<Map<String, dynamic>> getSupportTicket(String id) => get('/auth/driver/support/tickets/$id');
  static Future<Map<String, dynamic>> replySupportTicket(String id, String message) =>
      post('/auth/driver/support/tickets/$id', {'message': message}, auth: true);

  // ── Support chat (driver ↔ admin) ─────────────────────────
  static Future<Map<String, dynamic>> getSupportChat() => get('/auth/driver/support/chat');
  static Future<Map<String, dynamic>> sendSupportChat(String message) =>
      post('/auth/driver/support/chat', {'message': message}, auth: true);

  // ── ID card + profile picture ─────────────────────────────
  static Future<Map<String, dynamic>> getIdCard() => get('/auth/driver/idcard');
  static Future<Map<String, dynamic>> saveProfilePic(String url) =>
      post('/auth/driver/profile-pic', {'url': url}, auth: true);

  // ── Bank accounts + withdrawals ───────────────────────────
  // { driverName, banks: [{accountHolderName,bankName,accountNumber,ifscCode}] }
  static Future<Map<String, dynamic>> getBanks() => get('/auth/driver/banks');

  static Future<Map<String, dynamic>> addBank(Map<String, dynamic> bank) =>
      post('/auth/driver/banks', bank, auth: true);

  static Future<Map<String, dynamic>> requestWithdrawal(Map<String, dynamic> data) =>
      post('/auth/driver/withdraw', data, auth: true);

  static Future<Map<String, dynamic>> getWithdrawals() => get('/auth/driver/withdraw');

  // Create a Razorpay order for a subscription plan
  static Future<Map<String, dynamic>> createSubscriptionOrder(String planId) =>
      post('/auth/driver/subscription/order', {'planId': planId}, auth: true);

  // Activate a plan. Pass Razorpay fields when paid via gateway; omit for wallet payment.
  static Future<Map<String, dynamic>> buySubscription(String planId,
      {String? orderId, String? paymentId, String? signature}) =>
      post('/auth/driver/subscription/buy', {
        'planId': planId,
        if (orderId != null) 'orderId': orderId,
        if (paymentId != null) 'paymentId': paymentId,
        if (signature != null) 'signature': signature,
      }, auth: true);

  // Outstation phase / distance / night-halt update
  static Future<Map<String, dynamic>> updatePhase(String rideId, Map<String, dynamic> body) =>
      post('/rides/$rideId/phase', body, auth: true);

  // Rental actions: start / ping / wait / addStop / extend / end
  static Future<Map<String, dynamic>> rentalAction(String rideId, Map<String, dynamic> body) =>
      post('/rides/$rideId/rental', body, auth: true);

  // Hire-a-driver actions: start / ping / extend / end
  static Future<Map<String, dynamic>> hireAction(String rideId, Map<String, dynamic> body) =>
      post('/rides/$rideId/hire', body, auth: true);

  // Delivery actions: collected / deliver (with dropOtp)
  static Future<Map<String, dynamic>> deliveryAction(String rideId, Map<String, dynamic> body) =>
      post('/rides/$rideId/delivery', body, auth: true);

  // Outstation tolls: {action:'add', amount, clientRef, source?, lat?, lng?} / {action:'remove', tollId}
  static Future<Map<String, dynamic>> tollAction(String rideId, Map<String, dynamic> body) =>
      post('/rides/$rideId/toll', body, auth: true);

  // Multi-stop actions: reached / resume
  static Future<Map<String, dynamic>> stopAction(String rideId, Map<String, dynamic> body) =>
      post('/rides/$rideId/stop', body, auth: true);

  // ── Face verification ─────────────────────────────────────
  // Registration-time signature — the frontal capture also becomes profilePicUrl.
  static Future<Map<String, dynamic>> saveFaceSignature(List<double> embedding, String photoUrl) =>
      post('/auth/driver/face-signature', {'embedding': embedding, 'photoUrl': photoUrl}, auth: true);

  // { required, reason, hasSignature } — checked before letting the driver go online.
  static Future<Map<String, dynamic>> getFaceVerificationStatus() => get('/auth/driver/face-verification-status');

  // Standalone re-verify to clear a faceVerificationRequired lock.
  static Future<Map<String, dynamic>> reverifyFace(List<double> embedding, String photoUrl) =>
      post('/auth/driver/face-reverify', {'embedding': embedding, 'photoUrl': photoUrl}, auth: true);

  // Polled during an ongoing ride: { required, attemptId?, deadlineSec?, rideCancelled? }
  static Future<Map<String, dynamic>> checkFaceVerificationDue(String rideId) =>
      get('/rides/driver/face-check?rideId=$rideId');

  // Answer a mid-ride check: { matched, score } (or { late:true } / { alreadyResolved:true }).
  static Future<Map<String, dynamic>> respondFaceVerification(String attemptId, List<double> embedding, String photoUrl) =>
      post('/rides/driver/face-respond', {'attemptId': attemptId, 'embedding': embedding, 'photoUrl': photoUrl}, auth: true);
}
