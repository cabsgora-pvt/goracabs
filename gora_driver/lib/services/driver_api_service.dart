import 'dart:convert';
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
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> get(String path) async {
    final token = await getToken();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    final res = await http.get(Uri.parse('$baseUrl$path'), headers: headers);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<String?> uploadFile(XFile file) async {
    final bytes = await file.readAsBytes();
    final uri = Uri.parse('$baseUrl/upload');
    final request = http.MultipartRequest('POST', uri);
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

  // Auth
  static Future<Map<String, dynamic>> sendOtp(String phone) =>
      post('/auth/driver/send-otp', {'phone': phone});

  static Future<Map<String, dynamic>> verifyOtp(String phone, String otp) =>
      post('/auth/driver/verify-otp', {'phone': phone, 'otp': otp});

  static Future<Map<String, dynamic>> getProfile() => get('/auth/driver/profile');

  // Registration steps
  static Future<Map<String, dynamic>> savePersonal(Map<String, dynamic> data) =>
      post('/auth/driver/register/personal', data, auth: true);

  static Future<Map<String, dynamic>> saveVehicle(Map<String, dynamic> data) =>
      post('/auth/driver/register/vehicle', data, auth: true);

  static Future<Map<String, dynamic>> saveDocuments(List<Map<String, dynamic>> docs) =>
      post('/auth/driver/register/documents', {'documents': docs}, auth: true);

  static Future<Map<String, dynamic>> saveBank(Map<String, dynamic> data) =>
      post('/auth/driver/register/bank', data, auth: true);

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

  static Future<Map<String, dynamic>> getRide(String id) => get('/rides/$id');

  static Future<Map<String, dynamic>> rateRide(String id, int rating, String review) =>
      post('/rides/$id/rate', {'by': 'driver', 'rating': rating, 'review': review}, auth: true);

  static Future<Map<String, dynamic>> getTripHistory() =>
      get('/rides/driver/history');

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
}
