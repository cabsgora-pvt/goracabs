import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl = 'http://localhost:3000/api';

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
      if (data['url'] != null) return 'http://localhost:3000${data['url']}';
      return null;
    } catch (_) {
      return null;
    }
  }
}
