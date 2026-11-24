import 'dart:async';
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
    // A new session: the next expired-session reply may sign out again.
    _unauthorizedFired = false;
  }

  /// Called once when a request made WITH the current session token is
  /// answered 401 — the session expired or was signed out elsewhere. The app
  /// wires this to sign out (stop the online service, clear the session, go to
  /// login); the background ride-alert isolate wires its own.
  ///
  /// Before this every screen treated a 401 as just another error: the home
  /// poller saw "no rides" for ever and the driver sat online receiving nothing.
  static FutureOr<void> Function()? onUnauthorized;
  static bool _unauthorizedFired = false;

  /// Re-arms the one-shot 401 handler (a new login, or a test).
  static void resetUnauthorized() => _unauthorizedFired = false;

  static Future<void> _checkUnauthorized(int status, String? sentToken) async {
    if (status != 401 || sentToken == null || _unauthorizedFired) return;
    // Only the token that is still the session counts: a late reply to a
    // request made before a re-login must not sign the new session out.
    if (await getToken() != sentToken) return;
    if (_unauthorizedFired) return;
    _unauthorizedFired = true;
    final cb = onUnauthorized;
    if (cb != null) {
      try { await cb(); } catch (_) {}
    }
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
  ///
  /// A non-2xx reply also carries its HTTP code as `_status`, so callers can
  /// tell a refusal (409 RIDE_TAKEN, 423 OTP_LOCKED …) from a network failure.
  static Map<String, dynamic> _decode(http.Response res, {String? sentToken}) {
    unawaited(_checkUnauthorized(res.statusCode, sentToken));
    final ok = res.statusCode >= 200 && res.statusCode < 300;
    Map<String, dynamic> out;
    final body = res.body;
    if (body.trim().isEmpty) {
      out = {'error': 'No response from server (HTTP ${res.statusCode})'};
    } else {
      try {
        final v = jsonDecode(body);
        out = v is Map<String, dynamic> ? v : {'error': 'Unexpected response from server'};
      } catch (_) {
        out = {
          'error': res.statusCode >= 500
              ? 'Server error (${res.statusCode}). Please try again.'
              : 'Could not read the server response. Check your connection.',
        };
      }
    }
    if (!ok) out['_status'] = res.statusCode;
    return out;
  }

  static Future<Map<String, String>> _headers({bool auth = true}) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (auth) {
      final token = await getToken();
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  static String? _tokenOf(Map<String, String> h) {
    return h['Authorization']?.substring('Bearer '.length);
  }

  /// How long one API call may take. Without it a request on a lossy network
  /// could hang for minutes — the splash once sat on its spinner for 8 minutes
  /// waiting on the profile call. A timeout throws a TimeoutException, which
  /// every caller already handles the same way as a dropped connection.
  static const requestTimeout = Duration(seconds: 20);

  static Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body, {bool auth = false}) async {
    final headers = await _headers(auth: auth);
    final res = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: headers,
      body: jsonEncode(body),
    ).timeout(requestTimeout);
    return _decode(res, sentToken: _tokenOf(headers));
  }

  static Future<Map<String, dynamic>> delete(String path) async {
    final headers = await _headers();
    final res = await http.delete(Uri.parse('$baseUrl$path'), headers: headers).timeout(requestTimeout);
    return _decode(res, sentToken: _tokenOf(headers));
  }

  static Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body) async {
    final headers = await _headers();
    final res = await http.put(Uri.parse('$baseUrl$path'), headers: headers, body: jsonEncode(body)).timeout(requestTimeout);
    return _decode(res, sentToken: _tokenOf(headers));
  }

  static Future<Map<String, dynamic>> get(String path) async {
    final headers = await _headers();
    final res = await http.get(Uri.parse('$baseUrl$path'), headers: headers).timeout(requestTimeout);
    return _decode(res, sentToken: _tokenOf(headers));
  }

  /// How long one upload may take. Uploads had no limit at all, so on a weak
  /// network the proof-of-delivery and payment-QR spinners turned for ever.
  static const uploadTimeout = Duration(seconds: 45);

  /// The longest side a picked photo is uploaded at — pass to
  /// `pickImage(maxWidth:, maxHeight:)`. A 12 MP camera shot is several MB.
  static const maxImageSide = 1600.0;

  /// Why the last [uploadFile] / [uploadBytes] returned null, for the screen
  /// to show. Null after a successful upload.
  static String? lastUploadError;

  /// Uploads a picked photo; the full url, or null with [lastUploadError] set.
  /// Never throws and never hangs.
  static Future<String?> uploadFile(XFile file) async {
    Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      lastUploadError = 'Could not read the photo. Please try again.';
      return null;
    }
    return uploadBytes(bytes, file.name.isNotEmpty ? file.name : 'doc.jpg');
  }

  /// Uploads raw bytes (signature PNG, photos) → the full url, or null with
  /// [lastUploadError] set. Limited by [uploadTimeout]; never throws.
  static Future<String?> uploadBytes(Uint8List bytes, String filename) async {
    lastUploadError = null;
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/upload'));
      // /api/upload requires a signed-in caller.
      final token = await getToken();
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
      final res = await http.Response.fromStream(await request.send().timeout(uploadTimeout))
          .timeout(uploadTimeout);
      final data = _decode(res, sentToken: token);
      final url = data['url'];
      if (url is String && url.isNotEmpty) return AppConfig.imageUrl(url);
      lastUploadError = (data['error'] ?? 'Upload failed').toString();
      return null;
    } on TimeoutException {
      lastUploadError = 'Upload timed out — check your connection and try again.';
      return null;
    } catch (_) {
      lastUploadError = 'Upload failed — check your connection and try again.';
      return null;
    }
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

  /// With [finish] (registration's last step) the server also checks the
  /// required documents and submits the application: registrationStep
  /// 'submitted', status 'pending'. A missing one is a 400
  /// {error: 'Please upload: …', missing: [...]}.
  static Future<Map<String, dynamic>> saveDocuments(List<Map<String, dynamic>> docs, {bool finish = false}) =>
      post('/auth/driver/register/documents', {'documents': docs, if (finish) 'finish': true}, auth: true);

  /// Submits the application of a driver whose documents were saved by an
  /// older app build that still had a bank step (server registrationStep
  /// 'bank'). The server re-checks the saved documents and replies
  /// {success: true, registrationStep: 'submitted'} or 400 {error}.
  /// The reply carries the HTTP code as 'statusCode', so the caller can tell
  /// "documents incomplete" (4xx) from a server or network problem.
  static Future<Map<String, dynamic>> submitRegistration() async {
    final token = await getToken();
    final res = await http.post(
      Uri.parse('$baseUrl/auth/driver/register/submit'),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode(<String, dynamic>{}),
    ).timeout(requestTimeout);
    return {..._decode(res, sentToken: token), 'statusCode': res.statusCode};
  }

  // Register the device's FCM push token so the backend can wake the app with a
  // ride alert even when it's fully closed (Layer 2 — needs Firebase configured).
  static Future<Map<String, dynamic>> saveFcmToken(String token) =>
      post('/auth/driver/fcm-token', {'token': token}, auth: true);

  // Update driver preferences (currently: acceptsOutstation). Uses POST since CORS
  // allow-methods always includes POST. Returns the saved values.
  static Future<Map<String, dynamic>> updatePreferences(Map<String, dynamic> prefs) =>
      post('/auth/driver/preferences', prefs, auth: true);

  // Admin-defined registration documents: { documents: [{key,name,category,description,needsNumber,numberLabel,
  // frontLabel,backLabel,needsBack,needsExpiry,required,vehicleTypes,...}] }. With [vehicleType] the server
  // returns only the documents for that vehicle type.
  static Future<Map<String, dynamic>> getDocumentTypes({String? vehicleType}) {
    final t = (vehicleType ?? '').trim();
    return get(t.isEmpty ? '/document-types' : '/document-types?vehicleType=${Uri.encodeQueryComponent(t)}');
  }

  // Admin-defined ride preferences (pet friendly …): { preferences: [{key,name,description,icon,services}] }
  static Future<Map<String, dynamic>> getRidePreferences() => get('/ride-preferences');

  // ── My zone ──
  // { zoneId, zoneName, zoneAuto, zones, pendingRequest, history }
  static Future<Map<String, dynamic>> getMyZone() => get('/auth/driver/zone');

  static Future<Map<String, dynamic>> setZoneAuto(bool on) => put('/auth/driver/zone', {'zoneAuto': on});

  // ── Account requests (delete account / zone change) — the admin reviews them ──
  // { reasons, requests: [{id,kind,status,reason,note,toZoneName,createdAt,...}] }
  static Future<Map<String, dynamic>> getAccountRequests() => get('/auth/driver/account-request');

  static Future<Map<String, dynamic>> createAccountRequest(Map<String, dynamic> body) =>
      post('/auth/driver/account-request', body, auth: true);

  static Future<Map<String, dynamic>> withdrawAccountRequest(String id) =>
      delete('/auth/driver/account-request?id=${Uri.encodeQueryComponent(id)}');

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
  /// [lat]/[lng] only when there is a real fix: the server keeps the last
  /// known position otherwise.
  static Future<Map<String, dynamic>> setOnline(bool isOnline, [double? lat, double? lng]) =>
      post('/auth/driver/online', {
        'isOnline': isOnline,
        if (lat != null && lng != null) ...{'lat': lat, 'lng': lng},
      }, auth: true);

  /// A 400 INVALID_LOCATION / 422 LOCATION_JUMP reply only means this one
  /// point was not stored; callers keep pinging.
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

  /// The parsed body; a refusal also carries '_status' (403 / 409) and the
  /// server's `code` (RIDE_TAKEN, DRIVER_BUSY, WALLET_BLOCKED …). A repeat
  /// accept of a ride already ours answers {success, ride, repeated: true}.
  /// Throws on timeout / no connection — the caller then asks
  /// [getActiveRide] whether the accept went through anyway.
  static Future<Map<String, dynamic>> acceptRide(String id) => post('/rides/$id/accept', {}, auth: true);

  static Future<Map<String, dynamic>> rejectRide(String id) =>
      post('/rides/$id/reject', {}, auth: true);

  static Future<Map<String, dynamic>> arrivedRide(String id) =>
      post('/rides/$id/arrived', {}, auth: true);

  static Future<Map<String, dynamic>> startRide(String id, String otp) =>
      post('/rides/$id/start', {'otp': otp}, auth: true);

  /// Ends the trip and settles it: {success, paymentStatus, paymentMode,
  /// amountDue, awaitingPayment, paymentSwitchedToCash?, cashToCollect?, fare,
  /// commissionPercent, adminProfit, driverEarning, driverWalletBalance}. An
  /// online ride stays paymentStatus 'pending' until the rider pays.
  static Future<Map<String, dynamic>> completeRide(String id) =>
      post('/rides/$id/complete', {}, auth: true);

  /// Online ride: prompts the rider to pay → {success, awaitingPayment, amountDue}.
  static Future<Map<String, dynamic>> requestPayment(String id) =>
      post('/rides/$id/request-payment', {}, auth: true);

  /// The rider of a completed, unpaid online ride paid in cash instead:
  /// {success, paymentMode:'cash', paymentStatus:'paid', cashToCollect,
  /// commission, driverWalletBalance}; 409 paidOnline / 400 alreadyPaid.
  static Future<Map<String, dynamic>> collectCash(String id) =>
      post('/rides/$id/collect-cash', {}, auth: true);

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
      // The server takes the sender from the token; 409 CHAT_CLOSED once the trip is over.
      post('/rides/$rideId/messages', {'text': text}, auth: true);

  static Future<Map<String, dynamic>> getRide(String id) => get('/rides/$id');

  static Future<Map<String, dynamic>> rateRide(String id, int rating, String review) =>
      // Who rates is taken from the token. Completed rides only, once
      // (409 ALREADY_RATED / NOT_COMPLETED).
      post('/rides/$id/rate', {'rating': rating, 'review': review}, auth: true);

  /// Largest page the history endpoint serves.
  static const historyPageSize = 50;

  /// One page of completed/cancelled trips, newest first:
  /// {rides, page, limit, hasMore}.
  static Future<Map<String, dynamic>> getTripHistory({int page = 1, int limit = historyPageSize}) =>
      get('/rides/driver/history?page=$page&limit=${limit.clamp(1, historyPageSize)}');

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

  // ── Wallet recharge (Add balance) ──
  // { enabled, min, max, presets } — whether online recharge is open right now.
  static Future<Map<String, dynamic>> getRechargeConfig() => get('/auth/driver/wallet/recharge');

  static Future<Map<String, dynamic>> createRechargeOrder(int amount) =>
      post('/auth/driver/wallet/recharge', {'amount': amount}, auth: true);

  // The server credits what Razorpay says was paid, never an amount from here.
  static Future<Map<String, dynamic>> verifyRecharge({
    required String orderId,
    required String paymentId,
    required String signature,
  }) =>
      post('/auth/driver/wallet/recharge',
          {'orderId': orderId, 'paymentId': paymentId, 'signature': signature}, auth: true);

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
