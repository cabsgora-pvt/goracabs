import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// The rider's saved emergency contacts — one list, shared by the SOS screen
/// (which auto-calls the first one) and the Settings screen (which manages
/// the list). Previously each screen kept its own copy: Settings held an
/// in-memory mock list seeded with "John Doe"/"Jane Doe" that vanished on
/// restart, while SOS read a single separate "default contact" from
/// SharedPreferences that Settings never touched — adding a contact in
/// Settings did nothing for what SOS would actually call.
class EmergencyContactsStore {
  static const _key = 'sos_contacts_v1';

  static Future<List<Map<String, String>>> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => Map<String, String>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<Map<String, String>> contacts) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(contacts));
  }
}
