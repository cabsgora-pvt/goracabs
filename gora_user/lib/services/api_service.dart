import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import 'session_guard.dart';

class ApiService {
  static String get baseUrl => AppConfig.apiBaseUrl;

  // ── Auth token ────────────────────────────────────────────
  // Kept in the platform keystore (flutter_secure_storage), not in
  // SharedPreferences, where it sat in a plain XML file that also went into
  // device backups. A token saved by an older build is moved over once, the
  // first time it is read. Where the keystore cannot be used at all, the token
  // stays in SharedPreferences, as before, rather than signing the rider out.
  static const _tokenKey = 'user_token';
  static const FlutterSecureStorage _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static Future<String?> _secureRead() async {
    try {
      return await _secure.read(key: _tokenKey);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _secureWrite(String token) async {
    try {
      await _secure.write(key: _tokenKey, value: token);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> getToken() async {
    final s = await _secureRead();
    if (s != null && s.isNotEmpty) return s;
    // One-time migration from SharedPreferences.
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(_tokenKey);
    if (legacy == null || legacy.isEmpty) return null;
    if (await _secureWrite(legacy)) await prefs.remove(_tokenKey);
    return legacy;
  }

  static Future<void> saveToken(String token) async {
    SessionGuard.reset();
    final prefs = await SharedPreferences.getInstance();
    if (await _secureWrite(token)) {
      await prefs.remove(_tokenKey);
    } else {
      await prefs.setString(_tokenKey, token);
    }
  }

  static Future<void> clearToken() async {
    try {
      await _secure.delete(key: _tokenKey);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  // Google Places autocomplete (via backend proxy)
  static Future<List<Map<String, dynamic>>> placesAutocomplete(String query) async {
    if (query.trim().length < 2) return [];
    try {
      final res = await http.get(Uri.parse('$baseUrl/places/autocomplete?q=${Uri.encodeQueryComponent(query)}')).timeout(requestTimeout);
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (data['predictions'] as List?) ?? [];
      return list.map((p) => Map<String, dynamic>.from(p as Map)).toList();
    } catch (_) { return []; }
  }

  // Reverse geocode: lat/lng → address string. Strips Plus Codes defensively
  // (in case backend hasn't been updated to filter them).
  static final RegExp _plusCodeRe = RegExp(r'^[A-Z0-9]{4,8}\+[A-Z0-9]{2,4}\b', caseSensitive: false);
  static Future<String> reverseGeocode(double lat, double lng) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/places/reverse?lat=$lat&lng=$lng')).timeout(requestTimeout);
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      var addr = ((data['address'] as String?) ?? '').trim();
      if (addr.isEmpty) return '';
      // Strip leading Plus Code if present (e.g. "JJ4Q+39 Bopal" → "Bopal")
      if (_plusCodeRe.hasMatch(addr)) {
        addr = addr.replaceFirst(_plusCodeRe, '').replaceFirst(RegExp(r'^[\s,]+'), '').trim();
      }
      return addr;
    } catch (_) { return ''; }
  }

  /// A place's coordinates and address, or null.
  ///
  /// Always returns `lat` and `lng` as doubles and `address` as a String when
  /// it returns at all. The booking screens read them with `as num`, and an
  /// error answer ({error: ...}) or a coordinate sent as a string crashed them.
  static Future<Map<String, dynamic>?> placeDetails(String placeId) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/places/details?placeId=${Uri.encodeQueryComponent(placeId)}')).timeout(requestTimeout);
      final raw = jsonDecode(res.body);
      if (raw is! Map) return null;
      final data = Map<String, dynamic>.from(raw);
      final lat = toDoubleOrNull(data['lat']), lng = toDoubleOrNull(data['lng']);
      if (lat == null || lng == null) return null;
      data['lat'] = lat;
      data['lng'] = lng;
      // Strip Plus Code prefix from address if Google returned one
      var addr = (data['address'] is String ? data['address'] as String : '').trim();
      if (addr.isNotEmpty && _plusCodeRe.hasMatch(addr)) {
        addr = addr.replaceFirst(_plusCodeRe, '').replaceFirst(RegExp(r'^[\s,]+'), '').trim();
      }
      data['address'] = addr;
      return data;
    } catch (_) { return null; }
  }

  /// A finite double from a JSON value (number or numeric string), else null.
  static double? toDoubleOrNull(dynamic v) {
    final d = v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    return d != null && d.isFinite ? d : null;
  }

  /// How long one API call may take. Without it a request lost on a lossy
  /// network hung for about two minutes, and the ride-status poll (which skips
  /// while one is in flight) went quiet with it: "No driver found" reached the
  /// rider ~110 s after the server had closed the ride. A timeout throws a
  /// TimeoutException, handled like any dropped connection.
  static const requestTimeout = Duration(seconds: 20);

  /// An upload sends a photo over what may be a slow mobile link, so it gets
  /// longer than a plain call — but it no longer waits forever on a dead one.
  static const uploadTimeout = Duration(seconds: 60);

  static Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body, {bool auth = false}) async {
    final headers = {'Content-Type': 'application/json'};
    String? token;
    if (auth) {
      token = await getToken();
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    final res = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: headers,
      body: jsonEncode(body),
    ).timeout(requestTimeout);
    return _decode(res, sentToken: token != null);
  }

  /// Decodes an API response without ever throwing.
  ///
  /// The core post/get used a bare `jsonDecode(res.body) as Map`, which throws
  /// whenever the body is not a JSON object — common in the real world: an
  /// nginx 502 returns HTML, a 204 returns nothing, and captive-portal wifi
  /// returns a login page for every request. The FormatException then
  /// propagated out of whichever screen made the call.
  ///
  /// Callers already check `res['error']`, so failures are surfaced that way.
  /// An error answer (HTTP 400+) also carries its status as `httpStatus`, for
  /// callers that branch on a 402 or a 409 rather than on wording.
  ///
  /// A 401 to a request that carried the rider's token means the server no
  /// longer accepts it: [SessionGuard] signs the rider out, once, saying why
  /// when the server said (SESSION_REVOKED, ACCOUNT_DELETED). The account
  /// deletion answer of the profile call (401 {accountDeleted: true}) keeps its
  /// own flow.
  ///
  /// A 403 signs out only when the account itself is refused —
  /// {code: 'ACCOUNT_BLOCKED' | 'ACCOUNT_DELETED'}. Every other 403 (not this
  /// rider's ride, an account hold, the driver must end the trip, ...) answers
  /// that one request and leaves the rider signed in.
  static Map<String, dynamic> _decode(http.Response res, {bool sentToken = false}) {
    final out = _decodeBody(res);
    if (res.statusCode >= 400) out['httpStatus'] = res.statusCode;
    if (sentToken) {
      final reason = SessionGuard.signOutReasonFor(res.statusCode, out);
      if (reason != null) SessionGuard.onUnauthorized(reason: reason);
    }
    return out;
  }

  static Map<String, dynamic> _decodeBody(http.Response res) {
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

  static Future<Map<String, dynamic>> get(String path) async {
    final token = await getToken();
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    final res = await http.get(Uri.parse('$baseUrl$path'), headers: headers).timeout(requestTimeout);
    return _decode(res, sentToken: token != null);
  }

  static Future<Map<String, dynamic>> delete(String path) async {
    final token = await getToken();
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    final res = await http.delete(Uri.parse('$baseUrl$path'), headers: headers).timeout(requestTimeout);
    return _decode(res, sentToken: token != null);
  }

  // ── Account requests (delete my account) ─────────────────
  // GET → { reasons: [..], requests: [{id, kind, status, reason, note, createdAt, handledAt, adminNote}] }
  static Future<Map<String, dynamic>> getAccountRequests() => get('/auth/user/account-request');
  static Future<Map<String, dynamic>> requestAccountDeletion(String reason, String note) =>
      post('/auth/user/account-request', {'kind': 'delete', 'reason': reason, 'note': note}, auth: true);
  static Future<Map<String, dynamic>> withdrawAccountRequest(String id) =>
      delete('/auth/user/account-request?id=${Uri.encodeQueryComponent(id)}');

  // ── Notifications feed ───────────────────────────────────
  // { notifications: [{id, title, body, imageUrl, sentAt, type}] }
  static Future<Map<String, dynamic>> getNotifications() => get('/auth/user/notifications');

  // ── Admin-defined ride preferences ("Pet friendly", ...) ──
  // { preferences: [{id, key, name, description, icon, services}] }
  static Future<Map<String, dynamic>> getRidePreferences() => get('/ride-preferences');

  // ── App config (admin-managed content) ───────────────────
  // Only a config the server actually sent is kept: a failed fetch (offline,
  // a 502) used to be cached as {} for the rest of the session, so banners,
  // coupons and the update check stayed empty until a restart.
  static Map<String, dynamic>? _appConfigCache;
  static Future<Map<String, dynamic>> getAppConfig({bool force = false}) async {
    if (_appConfigCache != null && !force) return _appConfigCache!;
    try {
      final res = await get('/app-config?app=user');
      final cfg = res['config'];
      if (cfg is Map && res['error'] == null) {
        return _appConfigCache = cfg.cast<String, dynamic>();
      }
    } catch (_) {}
    return _appConfigCache ?? {};
  }

  // ── Nearby drivers (live vehicles on map) ────────────────
  // Returns a list of {id, lat, lng, heading, vehicleType} — no PII.
  static Future<List<Map<String, dynamic>>> getNearbyDrivers(
      double lat, double lng, {double radiusKm = 5, String? vehicleType}) async {
    try {
      final vt = (vehicleType != null && vehicleType.isNotEmpty)
          ? '&vehicleType=${Uri.encodeQueryComponent(vehicleType)}'
          : '';
      final res = await get('/rides/nearby-drivers?lat=$lat&lng=$lng&radius=$radiusKm$vt');
      final list = (res['drivers'] as List?) ?? const [];
      return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
    } catch (_) {
      return const [];
    }
  }

  // ── Wallet ───────────────────────────────────────────────
  static Future<Map<String, dynamic>> getWallet() => get('/wallet');
  // Money is added only through a verified Razorpay payment
  // (PaymentService.topUpWallet); POST /wallet is gone (410).
  //
  // Pays an outstation trip from the wallet BEFORE it is booked: no ride exists
  // yet, and /rides/book links the debit to the ride it creates. A ride paid by
  // wallet is debited by the SERVER when it completes — the app never charges it.
  static Future<Map<String, dynamic>> walletPrepay({required num amount, String? note}) =>
      post('/wallet/pay', {'amount': amount, 'note': ?note}, auth: true);

  /// Pays a COMPLETED wallet ride from the wallet - what is still due on a
  /// prepaid trip (prepaidShortfall). The server debits its own amountDue; no
  /// amount is sent. 200 {success, amount?, balance, alreadyPaid?}; 402
  /// {balance, amountDue} when the wallet is short; 409 {code: 'notPayableYet'}
  /// while the trip has not ended.
  static Future<Map<String, dynamic>> walletPayRide(String rideId) =>
      post('/wallet/pay', {'rideId': rideId}, auth: true);

  // ── Payment (Razorpay) ────────────────────────────────────
  static Map<String, dynamic>? _paymentConfigCache;
  static const Map<String, dynamic> _paymentConfigFallback = {
    'razorpay': {'enabled': false}, 'cashEnabled': true, 'walletEnabled': true,
  };
  // { razorpay: {enabled, keyId, mode}, cashEnabled, walletEnabled }
  // Only a real answer is cached. A failure (offline, a timeout, a 502 page)
  // used to be cached too, turning online payment off for the rest of the
  // session; now this call gets the safe fallback and the next one asks again.
  static Future<Map<String, dynamic>> getPaymentConfig({bool force = false}) async {
    if (_paymentConfigCache != null && !force) return _paymentConfigCache!;
    try {
      final res = await get('/payment/config');
      if (res['error'] == null && res['razorpay'] is Map) return _paymentConfigCache = res;
    } catch (_) {}
    return _paymentConfigCache ?? Map<String, dynamic>.from(_paymentConfigFallback);
  }

  /// Forgets the cached payment and app configs (sign-in change, tests).
  static void resetConfigCaches() {
    _paymentConfigCache = null;
    _appConfigCache = null;
  }

  // purpose: 'wallet' (top-up), 'outstation_prepay' (before booking, no ride),
  // or 'ride' + rideId (pay that ride; the server charges its own amountDue).
  static Future<Map<String, dynamic>> createRazorpayOrder({required num amount, String purpose = 'wallet', String? rideId}) =>
      post('/payment/razorpay/order', {'amount': amount, 'purpose': purpose, 'rideId': ?rideId}, auth: true);

  // The server credits or settles what Razorpay captured, never an amount the
  // app names, so none is sent.
  static Future<Map<String, dynamic>> verifyRazorpayPayment({
    required String orderId, required String paymentId, required String signature,
    String purpose = 'wallet', String? rideId,
  }) =>
      post('/payment/razorpay/verify', {
        'orderId': orderId, 'paymentId': paymentId, 'signature': signature, 'purpose': purpose,
        'rideId': ?rideId,
      }, auth: true);

  // ── Auth ──────────────────────────────────────────────────
  static Future<Map<String, dynamic>> sendOtp(String phone) =>
      post('/auth/user/send-otp', {'phone': phone});

  static Future<Map<String, dynamic>> verifyOtp(String phone, String otp) =>
      post('/auth/user/verify-otp', {'phone': phone, 'otp': otp});

  static Future<Map<String, dynamic>> register({
    required String name,
    required String city,
    required String email,
    required String idNumber,
    String profilePicUrl = '',
  }) =>
      post('/auth/user/register', {
        'name': name,
        'city': city,
        'email': email,
        'idNumber': idNumber,
        'profilePicUrl': profilePicUrl,
      }, auth: true);

  static Future<Map<String, dynamic>> getProfile() => get('/auth/user/profile');

  // Sliding session: a token at least a day old is swapped for a fresh 7-day
  // one. 200 {token, expiresIn, refreshAfter}; 409 {code: 'TOO_EARLY',
  // refreshAfter}; 401 / 403 {code} when the account is no longer accepted.
  static Future<Map<String, dynamic>> refreshSession() => post('/auth/refresh', {}, auth: true);

  // ── Referral (own code + live stats) ──────────────────────
  static Future<Map<String, dynamic>> getReferral() => get('/auth/user/referral');

  // ── Split fare ─────────────────────────────────────────────
  static Future<Map<String, dynamic>> getSplit(String rideId) => get('/rides/$rideId/split');
  static Future<Map<String, dynamic>> createSplit(String rideId, List<Map<String, String>> contacts) =>
      post('/rides/$rideId/split', {'contacts': contacts}, auth: true);
  static Future<Map<String, dynamic>> getSplitRequests() => get('/rides/split-requests');
  static Future<Map<String, dynamic>> paySplitShare(String rideId) =>
      post('/rides/$rideId/split/pay', {}, auth: true);

  // What cancelling this ride right now would cost — the same rule the
  // server applies when the cancel actually goes through, checked upfront.
  static Future<Map<String, dynamic>> getCancelFee(String rideId) =>
      get('/rides/$rideId/cancel-fee');

  // ── Rental packages (for pickup zone) ─────────────────────
  static Future<Map<String, dynamic>> getRentalPackages({
    required double pickupLat, required double pickupLng,
  }) => get('/rental/packages?pickupLat=$pickupLat&pickupLng=$pickupLng');

  // Rental actions the rider may take: addStop, and answering a driver's
  // extension request. addStop body: { action: 'addStop', address, lat, lng }.
  static Future<Map<String, dynamic>> rentalAction(String rideId, Map<String, dynamic> body) =>
      post('/rides/$rideId/rental', body, auth: true);

  // The driver asked to extend a rental or a hire (ride.pendingExtension) and
  // the rider answers; only the driver starts, ends or extends a trip. 409
  // NO_PENDING_EXTENSION when the request expired or was already answered.
  //
  // A confirm names the request the rider is looking at - its requestedAt and
  // amount, exactly as the ride's pendingExtension carried them - so a request
  // the driver swapped just before the tap is never the one applied: 409
  // EXTENSION_CHANGED {pendingExtension} (the current one, to confirm afresh),
  // 400 EXTENSION_DETAILS_REQUIRED when they are missing.
  static Future<Map<String, dynamic>> answerExtension(String rideId, String service,
          {required bool confirm, Map<String, dynamic>? extension}) =>
      post('/rides/$rideId/${service == 'hire_driver' ? 'hire' : 'rental'}', {
        'action': confirm ? 'confirm_extend' : 'decline_extend',
        if (confirm && extension != null) ...{
          'requestedAt': extension['requestedAt'],
          'amount': extension['amount'],
        },
      }, auth: true);

  // ── Ride engine ───────────────────────────────────────────
  // The quote is signed over its inputs, so each service must send here the
  // same inputs it books with: hire → totalHours + tripType; outstation →
  // tripType + stops (= multiStops); delivery → weightKg + stops; taxi → stops.
  static Future<Map<String, dynamic>> estimateFare({
    required double pickupLat, required double pickupLng,
    double? dropLat, double? dropLng, String service = 'taxi', double weightKg = 0,
    num totalHours = 0, String tripType = 'one_way', List<Map<String, dynamic>>? stops,
  }) => post('/fare/estimate', {
        'pickupLat': pickupLat, 'pickupLng': pickupLng,
        'dropLat': dropLat, 'dropLng': dropLng, 'service': service, 'weightKg': weightKg,
        'totalHours': totalHours, 'tripType': tripType,
        if (stops != null && stops.isNotEmpty) 'stops': stops,
      });

  /// Books a ride. [data] carries a `clientRequestId` — one per booking
  /// attempt, reused when a timed-out request is retried — so a retry gets the
  /// ride the first request made (`duplicate: true`) instead of a second one.
  static Future<Map<String, dynamic>> bookRide(Map<String, dynamic> data) =>
      post('/rides/book', data, auth: true);

  /// One ride. [lite] leaves out the chat (`messages`): the live ride screen
  /// polls every 3 s and never shows it - the chat screen reads its own
  /// endpoint (/rides/{id}/messages).
  static Future<Map<String, dynamic>> getRide(String id, {bool lite = false}) =>
      get('/rides/$id${lite ? '?lite=1' : ''}');

  /// The rider's one current ride, small: {ride: {...} | null, blocksBooking}.
  /// The newest pending / accepted / arrived / ongoing ride, or one still
  /// awaiting payment. Home polls this instead of the whole history.
  static Future<Map<String, dynamic>> getActiveRide() => get('/rides/active');

  /// The public live-tracking link's token, for sharing this ride:
  /// {shareToken, path: '/track/{token}'}. The tracker answers only to it.
  static Future<Map<String, dynamic>> getShareToken(String rideId) => get('/rides/$rideId/share-token');

  /// Tells Gora something is wrong with the driver of a live ride.
  /// kind: 'driver_unreachable' | 'driver_not_arrived' | 'other'.
  /// -> {success, needsReview, cancelled?, cancellationFee?, status}. A
  /// driver_unreachable report on an accepted / arrived ride also cancels it,
  /// with no fee. 429 RATE_LIMITED, 409 NOT_ACTIVE.
  static Future<Map<String, dynamic>> reportRideIssue(String rideId, String kind, {String note = ''}) =>
      post('/rides/$rideId/report-issue', {'kind': kind, if (note.trim().isNotEmpty) 'note': note.trim()}, auth: true);

  /// What the server WILL take off for [code] on this trip - nothing redeemed.
  /// -> {valid, discount, reason?, code, fare, tip, payable}. For an outstation
  /// trip paid upfront, `payable` is exactly what the booking requires.
  static Future<Map<String, dynamic>> previewPromo({
    required String code, required String service, required num fare, num tip = 0,
    double? pickupLat, double? pickupLng,
  }) => post('/promos/preview', {
        'code': code, 'service': service, 'fare': fare, 'tip': tip,
        'pickupLat': ?pickupLat, 'pickupLng': ?pickupLng,
      }, auth: true);

  // Returns { polyline, distanceKm, durationMin } — used to draw route + show road ETA
  static Future<Map<String, dynamic>> getDirections({
    required double originLat, required double originLng,
    required double destLat, required double destLng,
  }) => get('/directions?originLat=$originLat&originLng=$originLng&destLat=$destLat&destLng=$destLng');

  // Polled by rider during accepted/arrived/ongoing ride to track driver
  // position. `driver` is null outside those statuses.
  static Future<Map<String, dynamic>> getDriverLocation(String rideId) =>
      get('/rides/$rideId/driver-location');

  // ── SOS alert (raised when the rider taps SOS) ────────────
  static Future<Map<String, dynamic>> sendSosAlert(Map<String, dynamic> body) =>
      post('/support/sos-alert', body, auth: true);

  // ── In-ride chat (rider ↔ driver) ─────────────────────────
  static Future<Map<String, dynamic>> getRideMessages(String rideId) =>
      get('/rides/$rideId/messages');
  // The sender is whoever the token says. 409 CHAT_CLOSED outside a live ride.
  static Future<Map<String, dynamic>> sendRideMessage(String rideId, String text) =>
      post('/rides/$rideId/messages', {'text': text}, auth: true);

  // Report a toll the driver entered on an outstation trip; opens a support ticket.
  // reason: 'no_toll' | 'wrong_amount' | 'other'
  static Future<Map<String, dynamic>> reportToll(String rideId, String tollId, String reason, String note) =>
      post('/rides/$rideId/toll', {'action': 'report', 'tollId': tollId, 'reason': reason, if (note.isNotEmpty) 'note': note}, auth: true);

  static Future<Map<String, dynamic>> cancelRide(String id, String reason) =>
      post('/rides/$id/cancel', {'cancelledBy': 'rider', 'reason': reason}, auth: true);

  // Who rates is taken from the token. Completed rides only, and once:
  // 409 ALREADY_RATED / NOT_COMPLETED.
  static Future<Map<String, dynamic>> rateRide(String id, int rating, String review) =>
      post('/rides/$id/rate', {'rating': rating, 'review': review}, auth: true);

  /// The rider's ride history, newest first, a page at a time:
  /// {rides, page, limit, hasMore}. (It used to send everything, chat and all.)
  static Future<Map<String, dynamic>> getMyRides({int limit = 20, int page = 1}) =>
      get('/rides/user?limit=$limit&page=$page');
  // Parcels addressed TO me (I'm the receiver) — matched by phone. Needs the
  // rider's token (sent by get) and returns only the fields a receiver needs.
  static Future<Map<String, dynamic>> getIncomingParcels() => get('/rides/delivery/incoming');

  // ── Upload profile picture ────────────────────────────────
  static Future<String?> uploadProfilePic(XFile xfile) async {
    try {
      final Uint8List bytes = await xfile.readAsBytes();
      final uri = Uri.parse('$baseUrl/upload');
      final request = http.MultipartRequest('POST', uri);
      // /api/upload now requires a signed-in caller.
      final token = await getToken();
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      request.files.add(http.MultipartFile.fromBytes(
        'file', bytes,
        filename: xfile.name.isNotEmpty ? xfile.name : 'profile.jpg',
      ));
      final url = await _sendUpload(request);
      return url == null ? null : AppConfig.imageUrl(url);
    } catch (_) {
      return null;
    }
  }

  // Upload an image, returns the RELATIVE url (/uploads/..) for storing on a ride
  static Future<String?> uploadImage(XFile xfile) async {
    try {
      final Uint8List bytes = await xfile.readAsBytes();
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/upload'));
      final token = await getToken();
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: xfile.name.isNotEmpty ? xfile.name : 'parcel.jpg'));
      return await _sendUpload(request);
    } catch (_) { return null; }
  }

  /// Sends an upload with a timeout and returns the stored file's url, or null.
  /// Goes through the zone's http client (http.runWithClient), like every call.
  static Future<String?> _sendUpload(http.MultipartRequest request) async {
    final client = http.Client();
    try {
      final streamed = await client.send(request).timeout(uploadTimeout);
      final res = await http.Response.fromStream(streamed).timeout(uploadTimeout);
      final data = jsonDecode(res.body);
      final url = data is Map ? data['url'] : null;
      return url is String && url.isNotEmpty ? url : null;
    } finally {
      client.close();
    }
  }
}
