import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/session_refresh.dart';

class UserProvider extends ChangeNotifier {
  Map<String, dynamic>? _user;
  bool _loading = false;
  bool _accountDeleted = false;

  Map<String, dynamic>? get user => _user;
  bool get loading => _loading;

  /// The server said this account was deleted (an admin approved the rider's
  /// deletion request). The token has already been cleared; the home screen
  /// listens for this and sends the rider back to the welcome screen.
  bool get accountDeleted => _accountDeleted;

  /// The admin's hold on this account, or null: {kind, reason, message}.
  /// A held rider cannot book; the home screen shows [message] in a banner.
  Map<String, dynamic>? get hold {
    final h = _user?['hold'];
    return h is Map ? Map<String, dynamic>.from(h) : null;
  }

  String get name => _user?['name'] ?? '';
  String get phone => _user?['phone'] ?? '';
  String get email => _user?['email'] ?? '';
  String get city => _user?['city'] ?? '';
  String get idNumber => _user?['idNumber'] ?? '';
  String get profilePicUrl {
    final raw = (_user?['profilePicUrl'] as String? ?? '');
    if (raw.isEmpty) return '';
    final m = RegExp(r'/uploads/[^\s?#]+').firstMatch(raw);
    return m != null ? m.group(0)! : raw;
  }

  Future<void> loadProfile() async {
    final token = await ApiService.getToken();
    if (token == null) return;
    _loading = true;
    notifyListeners();
    try {
      final res = await ApiService.getProfile();
      if (res['accountDeleted'] == true) {
        // 401 {accountDeleted: true}: sign out for good.
        await ApiService.clearToken();
        _user = null;
        _accountDeleted = true;
      } else if (res['user'] != null) {
        _user = Map<String, dynamic>.from(res['user']);
        // When the token may be swapped for a fresh one (sliding session).
        SessionRefresher.noteRefreshAfter(res['refreshAfter']);
        SessionRefresher.maybeRefresh();
      }
    } catch (_) {}
    _loading = false;
    notifyListeners();
  }

  void setUser(Map<String, dynamic> userData) {
    _user = Map<String, dynamic>.from(userData);
    notifyListeners();
  }

  Future<bool> updateProfile({
    required String name,
    required String city,
    required String email,
    required String idNumber,
    String? profilePicUrl,
  }) async {
    try {
      final res = await ApiService.register(
        name: name,
        city: city,
        email: email,
        idNumber: idNumber,
        profilePicUrl: profilePicUrl ?? this.profilePicUrl,
      );
      if (res['success'] == true && res['user'] != null) {
        _user = Map<String, dynamic>.from(res['user']);
        notifyListeners();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  void clear() {
    _user = null;
    _accountDeleted = false;
    notifyListeners();
  }
}
