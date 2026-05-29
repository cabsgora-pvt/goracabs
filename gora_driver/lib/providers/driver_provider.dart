import 'package:flutter/material.dart';
import '../services/driver_api_service.dart';

class DriverProvider extends ChangeNotifier {
  Map<String, dynamic>? _data;
  bool _loading = false;

  Map<String, dynamic>? get data => _data;
  bool get loading => _loading;

  String get name => _data?['name'] as String? ?? '';
  String get phone => _data?['phone'] as String? ?? '';
  String get email => _data?['email'] as String? ?? '';
  String get state => _data?['state'] as String? ?? '';
  String get profilePicUrl => _data?['profilePicUrl'] as String? ?? '';
  String get vehicleNumber => _data?['vehicleRegistrationNumber'] as String? ?? _data?['vehicleNumber'] as String? ?? '';
  String get vehicleModel => _data?['vehicleModel'] as String? ?? '';
  String get vehicleType => _data?['selectedVehicleTypeName'] as String? ?? _data?['vehicleType'] as String? ?? '';
  String get rating => (_data?['rating'] ?? 0).toString();
  String get totalRides => (_data?['totalRides'] ?? 0).toString();
  List<Map<String, dynamic>> get documents {
    final docs = _data?['documents'] as List?;
    if (docs == null) return [];
    return docs.map((d) => Map<String, dynamic>.from(d as Map)).toList();
  }

  Future<void> loadProfile() async {
    final token = await DriverApiService.getToken();
    if (token == null) return;
    _loading = true;
    notifyListeners();
    try {
      final res = await DriverApiService.getProfile();
      if (res['driver'] != null) {
        _data = Map<String, dynamic>.from(res['driver'] as Map);
      }
    } catch (_) {}
    _loading = false;
    notifyListeners();
  }

  void setData(Map<String, dynamic> d) {
    _data = Map<String, dynamic>.from(d);
    notifyListeners();
  }

  void clear() { _data = null; notifyListeners(); }
}
