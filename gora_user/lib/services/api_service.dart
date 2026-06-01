import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

class ApiService {
  static String get baseUrl => AppConfig.apiBaseUrl;

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_token');
  }

  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_token', token);
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_token');
  }

  // Google Places autocomplete (via backend proxy)
  static Future<List<Map<String, dynamic>>> placesAutocomplete(String query) async {
    if (query.trim().length < 2) return [];
    try {
      final res = await http.get(Uri.parse('$baseUrl/places/autocomplete?q=${Uri.encodeQueryComponent(query)}'));
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
      final res = await http.get(Uri.parse('$baseUrl/places/reverse?lat=$lat&lng=$lng'));
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

  static Future<Map<String, dynamic>?> placeDetails(String placeId) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/places/details?placeId=$placeId'));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['lat'] == null) return null;
      // Strip Plus Code prefix from address if Google returned one
      var addr = ((data['address'] as String?) ?? '').trim();
      if (addr.isNotEmpty && _plusCodeRe.hasMatch(addr)) {
        addr = addr.replaceFirst(_plusCodeRe, '').replaceFirst(RegExp(r'^[\s,]+'), '').trim();
        data['address'] = addr;
      }
      return data;
    } catch (_) { return null; }
  }

  static Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body, {bool auth = false}) async {
    final headers = {'Content-Type': 'application/json'};
    if (auth) {
      final token = await getToken();
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    final res = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: headers,
      body: jsonEncode(body),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> get(String path) async {
    final token = await getToken();
    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    final res = await http.get(Uri.parse('$baseUrl$path'), headers: headers);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

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

  // ── Rental packages (for pickup zone) ─────────────────────
  static Future<Map<String, dynamic>> getRentalPackages({
    required double pickupLat, required double pickupLng,
  }) => get('/rental/packages?pickupLat=$pickupLat&pickupLng=$pickupLng');

  // ── Ride engine ───────────────────────────────────────────
  static Future<Map<String, dynamic>> estimateFare({
    required double pickupLat, required double pickupLng,
    double? dropLat, double? dropLng, String service = 'taxi',
  }) => post('/fare/estimate', {
        'pickupLat': pickupLat, 'pickupLng': pickupLng,
        'dropLat': dropLat, 'dropLng': dropLng, 'service': service,
      });

  static Future<Map<String, dynamic>> bookRide(Map<String, dynamic> data) =>
      post('/rides/book', data, auth: true);

  static Future<Map<String, dynamic>> getRide(String id) => get('/rides/$id');

  // Returns { polyline, distanceKm, durationMin } — used to draw route + show road ETA
  static Future<Map<String, dynamic>> getDirections({
    required double originLat, required double originLng,
    required double destLat, required double destLng,
  }) => get('/directions?originLat=$originLat&originLng=$originLng&destLat=$destLat&destLng=$destLng');

  // Polled by rider during accepted/arrived/ongoing ride to track driver position
  static Future<Map<String, dynamic>> getDriverLocation(String rideId) =>
      get('/rides/$rideId/driver-location');

  static Future<Map<String, dynamic>> cancelRide(String id, String reason) =>
      post('/rides/$id/cancel', {'cancelledBy': 'rider', 'reason': reason}, auth: true);

  static Future<Map<String, dynamic>> rateRide(String id, int rating, String review) =>
      post('/rides/$id/rate', {'by': 'rider', 'rating': rating, 'review': review}, auth: true);

  static Future<Map<String, dynamic>> getMyRides() => get('/rides/user');

  // ── Upload profile picture ────────────────────────────────
  static Future<String?> uploadProfilePic(XFile xfile) async {
    try {
      final Uint8List bytes = await xfile.readAsBytes();
      final uri = Uri.parse('$baseUrl/upload');
      final request = http.MultipartRequest('POST', uri);
      request.files.add(http.MultipartFile.fromBytes(
        'file', bytes,
        filename: xfile.name.isNotEmpty ? xfile.name : 'profile.jpg',
      ));
      final streamed = await request.send();
      final res = await http.Response.fromStream(streamed);
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['url'] != null) return AppConfig.imageUrl(data['url'] as String);
      return null;
    } catch (_) {
      return null;
    }
  }
}
