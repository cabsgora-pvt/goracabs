import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What a driver has typed into a registration step, kept on the phone until
/// the application is submitted — so a call, a closed app or a crash in the
/// middle of the form does not throw it away.
///
/// One entry per step ([personal], [vehicle]). A restored draft only fills
/// fields that are still empty: what the server already holds (a
/// resubmission's prefill) is never overwritten by an older draft.
class RegistrationDraft {
  RegistrationDraft._();

  static const personal = 'personal';
  static const vehicle = 'vehicle';
  static const steps = [personal, vehicle];

  static String keyOf(String step) => 'reg_draft_$step';

  /// Every draft's preference key (cleared on sign-out too).
  static List<String> get keys => [for (final s in steps) keyOf(s)];

  static Future<Map<String, String>> load(String step) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(keyOf(step));
      if (raw == null || raw.isEmpty) return {};
      final v = jsonDecode(raw);
      if (v is! Map) return {};
      return {
        for (final e in v.entries)
          if (e.value != null && e.value.toString().isNotEmpty) e.key.toString(): e.value.toString(),
      };
    } catch (_) {
      return {};
    }
  }

  static Future<void> save(String step, Map<String, String?> values) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final clean = {
        for (final e in values.entries)
          if (e.value != null && e.value!.trim().isNotEmpty) e.key: e.value!,
      };
      if (clean.isEmpty) {
        await prefs.remove(keyOf(step));
      } else {
        await prefs.setString(keyOf(step), jsonEncode(clean));
      }
    } catch (_) {}
  }

  /// True once the application went in: pages closing after that (the
  /// submit clears the stack) must not save their draft back.
  static bool sealed = false;

  /// The application went in: no draft is needed any more.
  static Future<void> clear() async {
    sealed = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in keys) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }

  /// [c]'s text, from [draft][key] when the field is still empty.
  static void restoreInto(TextEditingController c, Map<String, String> draft, String key) {
    final v = draft[key];
    if (v != null && v.isNotEmpty && c.text.trim().isEmpty) c.text = v;
  }
}

/// Saves a step's draft at most twice a second while the driver types.
class DraftSaver {
  DraftSaver(this.step, this.values);

  final String step;
  final Map<String, String?> Function() values;
  Timer? _t;

  void schedule() {
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 500), flush);
  }

  /// Saves now (also on leaving the page).
  Future<void> flush() {
    _t?.cancel();
    _t = null;
    if (RegistrationDraft.sealed) return Future.value();
    return RegistrationDraft.save(step, values());
  }

  void cancel() => _t?.cancel();
}
