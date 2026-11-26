import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import 'phone.dart';

/// The rider's saved emergency contacts — one list, shared by the SOS screen
/// (which auto-calls the first one) and the Settings screen (which manages
/// the list). Previously each screen kept its own copy: Settings held an
/// in-memory mock list seeded with "John Doe"/"Jane Doe" that vanished on
/// restart, while SOS read a single separate "default contact" from
/// SharedPreferences that Settings never touched — adding a contact in
/// Settings did nothing for what SOS would actually call.
///
/// The list now lives on the server (GET/POST/DELETE /api/user/sos-contacts),
/// so it survives a reinstall or a new phone. The copy in SharedPreferences
/// is the offline cache SOS calls from when the network is down. A contact
/// with an `id` is on the server; one without (saved by an older build, or
/// added offline) is uploaded by the next [sync].
class EmergencyContactsStore {
  static const _key = 'sos_contacts_v1';
  static const maxContacts = 5;

  /// The cached list (no network).
  static Future<List<Map<String, String>>> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), (v ?? '').toString())))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<Map<String, String>> contacts) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode(contacts));
    } catch (_) {}
  }

  static Map<String, String> _fromServer(Map c) => {
        'id': (c['id'] ?? '').toString(),
        'name': (c['name'] ?? '').toString(),
        'phone': (c['phone'] ?? '').toString(),
        'relation': (c['relation'] ?? '').toString(),
      };

  /// The server's list, after uploading any contact only this phone has (the
  /// one-time migration of lists saved before contacts were kept on the
  /// server). Cached for offline use. Offline, the cached list is returned.
  static Future<List<Map<String, String>>> sync() async {
    final local = await load();
    Map<String, dynamic> res;
    try {
      res = await ApiService.getSosContacts();
    } catch (_) {
      return local;
    }
    final raw = res['contacts'];
    if (res['error'] != null || raw is! List) return local;
    final server = raw.whereType<Map>().map(_fromServer).toList();

    final pending = local.where((c) => (c['id'] ?? '').isEmpty).toList();
    if (pending.isNotEmpty) {
      final known = server.map((c) => c['phone']).toSet();
      for (final c in pending) {
        final phone = indianMobile(c['phone'] ?? '');
        if (phone == null || known.contains(phone)) continue; // not a mobile, or already there
        if (server.length >= maxContacts) break;
        try {
          final r = await ApiService.addSosContact(c['name'] ?? 'Contact', phone, relation: c['relation'] ?? '');
          final added = r['contact'];
          if (added is Map) {
            server.add(_fromServer(added));
            known.add(phone);
          }
        } catch (_) {
          // Lost the connection mid-way: keep what is still local-only for next time.
          final keep = [...server, ...pending.where((p) => !known.contains(indianMobile(p['phone'] ?? '')))];
          await save(keep);
          return keep;
        }
      }
    }
    await save(server);
    return server;
  }

  /// Adds a contact. Returns null on success, else the message to show.
  /// Offline, the contact is kept on this phone and uploaded by the next sync.
  static Future<String?> add(String name, String phoneInput, {String relation = ''}) async {
    final n = name.trim();
    if (n.isEmpty) return 'Enter a name';
    final phone = indianMobile(phoneInput);
    if (phone == null) return 'Enter a valid 10-digit mobile number';
    final list = await load();
    if (list.any((c) => indianMobile(c['phone'] ?? '') == phone)) return 'This number is already saved';
    if (list.length >= maxContacts) return 'You can keep up to $maxContacts emergency contacts';
    Map<String, dynamic> res;
    try {
      res = await ApiService.addSosContact(n, phone, relation: relation.trim());
    } catch (_) {
      await save([...list, {'name': n, 'phone': phone, 'relation': relation.trim()}]);
      return null;
    }
    final c = res['contact'];
    if (c is Map) {
      await save([...list, _fromServer(c)]);
      return null;
    }
    return (res['error'] ?? 'Could not save the contact').toString();
  }

  /// Removes [contact]. Returns null on success, else the message to show.
  /// One on the server needs the server: removing it only here would bring it
  /// back on the next sync.
  static Future<String?> remove(Map<String, String> contact) async {
    final id = contact['id'] ?? '';
    if (id.isNotEmpty) {
      Map<String, dynamic> res;
      try {
        res = await ApiService.deleteSosContact(id);
      } catch (_) {
        return "You're offline. Connect to the internet to remove a contact.";
      }
      if (res['error'] != null && res['httpStatus'] != 404) {
        return (res['error'] ?? 'Could not remove the contact').toString();
      }
    }
    final list = await load();
    list.removeWhere((c) => id.isNotEmpty ? c['id'] == id : (c['phone'] == contact['phone'] && c['name'] == contact['name']));
    await save(list);
    return null;
  }
}
