import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A coupon the rider chose on the Offers screen ("Apply") for their next
/// booking. The next PaymentCouponBar (any booking screen) picks it up and
/// checks it against that trip with POST /promos/preview — the discount is
/// always the server's. It is cleared once the server has accepted or
/// refused it, and it expires after a day so a forgotten tap does not
/// resurface weeks later.
class PendingCoupon {
  static const _key = 'pending_coupon_v1';
  static const maxAge = Duration(hours: 24);

  final String code;

  /// The service the offer is for ('taxi', 'rental', ...) or '' for any.
  final String service;
  final DateTime savedAt;
  const PendingCoupon(this.code, {this.service = '', required this.savedAt});

  /// Whether a bar booking [barService] should use it.
  bool appliesTo(String barService) => service.isEmpty || service == barService;

  static Future<void> save(String code, {String service = '', DateTime? now}) async {
    final c = code.trim().toUpperCase();
    if (c.isEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode({
        'code': c,
        'service': normalizeService(service),
        'savedAt': (now ?? DateTime.now()).toIso8601String(),
      }));
    } catch (_) {}
  }

  /// The pending coupon, or null (none, unreadable or expired).
  static Future<PendingCoupon?> load({DateTime? now}) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null || raw.isEmpty) return null;
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      final code = (m['code'] ?? '').toString();
      final at = DateTime.tryParse((m['savedAt'] ?? '').toString());
      if (code.isEmpty || at == null) return null;
      if ((now ?? DateTime.now()).difference(at) > maxAge) {
        await p.remove(_key);
        return null;
      }
      return PendingCoupon(code, service: (m['service'] ?? '').toString(), savedAt: at);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_key);
    } catch (_) {}
  }

  /// The admin's coupon `service` label ("Ride", "Delivery", "rental", "All")
  /// as the booking screens name services, or '' for any.
  static String normalizeService(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.isEmpty || s == 'all' || s == 'any') return '';
    if (s == 'ride' || s == 'rides' || s == 'cab' || s == 'taxi') return 'taxi';
    if (s.contains('parcel') || s.contains('deliver')) return 'delivery';
    if (s.contains('rental')) return 'rental';
    if (s.contains('outstation')) return 'outstation';
    if (s.contains('hire') || s.contains('driver')) return 'hire_driver';
    return '';
  }
}
