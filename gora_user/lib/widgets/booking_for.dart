import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/user_provider.dart';

import '../utils/phone.dart';
import '../utils/phone_input_formatter.dart';
import 'ride_ui/ride_sheet.dart';
import 'ride_ui/ride_tokens.dart';

/// Who a ride is for: the rider themself, or someone else (name + mobile).
///
/// Sent with every booking as `bookingFor: 'self' | 'other'` plus
/// `passengerName` / `passengerPhone` for 'other'. The server refuses an
/// 'other' booking without a valid name and phone (400 PASSENGER_REQUIRED)
/// and one whose phone is the rider's own (400 PASSENGER_IS_RIDER); the
/// driver sees the passenger's name on the request and name + phone once
/// the ride is accepted.
class BookingFor {
  final String? name;
  final String? phone; // 10-digit Indian mobile when set
  const BookingFor.self() : name = null, phone = null;
  const BookingFor.other(String this.name, String this.phone);

  bool get isOther => name != null && phone != null;

  /// The fields the booking body carries.
  Map<String, dynamic> toBody() => isOther
      ? {'bookingFor': 'other', 'passengerName': name, 'passengerPhone': phone}
      : {'bookingFor': 'self'};

  /// The chip label: "Myself" / "Asha".
  String get label => isOther ? name! : 'Myself';

  Map<String, String> toJson() => {'name': name ?? '', 'phone': phone ?? ''};

  @override
  bool operator ==(Object other) => other is BookingFor && other.name == name && other.phone == phone;
  @override
  int get hashCode => Object.hash(name, phone);
}

/// "+91 98765 43210".
String formatIndianMobile(String tenDigits) =>
    tenDigits.length == 10 ? '+91 ${tenDigits.substring(0, 5)} ${tenDigits.substring(5)}' : tenDigits;

/// Checks a passenger entry. Returns an error message, or null when valid.
String? validatePassenger(String name, String phone, {String? riderPhone}) {
  final n = name.trim();
  if (n.length < 2) return "Enter the passenger's name";
  if (n.length > 60) return 'Name is too long';
  final p = indianMobile(phone);
  if (p == null) return 'Enter a valid 10-digit mobile number';
  final mine = riderPhone == null ? null : indianMobile(riderPhone);
  if (mine != null && mine == p) return 'That is your own number — choose "Myself" instead';
  return null;
}

/// What to tell the rider when the server refused a booking for its
/// passenger, or null for any other failure.
String? passengerErrorMessage(Map<String, dynamic> res) {
  switch (res['code']) {
    case 'PASSENGER_REQUIRED':
      return "Add the passenger's name and a valid 10-digit mobile number, then book again.";
    case 'PASSENGER_IS_RIDER':
      return 'That passenger number is your own — choose "Myself" instead.';
  }
  return null;
}

/// "Ride for Asha · +91 98765 43210" for a ride booked for someone else
/// (`bookingFor: 'other'` with `passengerName`), or null.
String? passengerLine(Map<String, dynamic> ride) {
  final name = (ride['passengerName'] ?? '').toString().trim();
  if (ride['bookingFor'] != 'other' && name.isEmpty) return null;
  if (name.isEmpty) return null;
  final phone = indianMobile((ride['passengerPhone'] ?? '').toString());
  return phone == null ? 'Ride for $name' : 'Ride for $name · ${formatIndianMobile(phone)}';
}

/// The last few people the rider booked for, newest first (max [max]).
class RecentPassengers {
  static const key = 'recent_passengers_v1';
  static const max = 5;

  static Future<List<BookingFor>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return const [];
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      final out = <BookingFor>[];
      for (final e in list) {
        if (e is! Map) continue;
        final n = (e['name'] ?? '').toString().trim();
        final p = indianMobile((e['phone'] ?? '').toString());
        if (n.length >= 2 && p != null) out.add(BookingFor.other(n, p));
      }
      return out.take(max).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Puts [p] first (replacing an entry with the same phone) and keeps [max].
  static List<BookingFor> merge(List<BookingFor> current, BookingFor p) {
    if (!p.isOther) return current;
    return [p, ...current.where((c) => c.phone != p.phone)].take(max).toList();
  }

  static Future<void> remember(BookingFor p) async {
    if (!p.isOther) return;
    try {
      final next = merge(await load(), p);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode([for (final e in next) e.toJson()]));
    } catch (_) {}
  }
}

/// The signed-in rider's phone, or null (no provider above, as in tests).
String? riderPhoneOf(BuildContext context) {
  try {
    final p = Provider.of<UserProvider>(context, listen: false).phone;
    return p.isEmpty ? null : p;
  } catch (_) {
    return null;
  }
}

/// "Booking for: Myself ▾" — opens [showBookingForSheet].
class BookingForChip extends StatelessWidget {
  final BookingFor value;
  final String? riderPhone;
  final ValueChanged<BookingFor> onChanged;
  const BookingForChip({super.key, required this.value, required this.onChanged, this.riderPhone});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: RideUi.tile(context),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        key: const ValueKey('booking-for-chip'),
        borderRadius: BorderRadius.circular(22),
        onTap: () async {
          final picked = await showBookingForSheet(context, current: value,
              riderPhone: riderPhone ?? riderPhoneOf(context));
          if (picked != null) onChanged(picked);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(value.isOther ? Icons.people_alt_rounded : Icons.person_rounded, size: 16, color: RideUi.ink(context)),
            const SizedBox(width: 6),
            Text('Booking for: ', style: RideUi.caption(context, size: 12.5)),
            Flexible(
              child: Text(value.label, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: RideUi.body(context, size: 13, weight: FontWeight.w800)),
            ),
            Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: RideUi.ink(context)),
          ]),
        ),
      ),
    );
  }
}

/// Myself / Someone else (name + mobile, with recent passengers). Returns
/// the choice, or null when dismissed.
Future<BookingFor?> showBookingForSheet(BuildContext context,
    {required BookingFor current, String? riderPhone}) {
  return showModalBottomSheet<BookingFor>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _BookingForSheet(current: current, riderPhone: riderPhone),
  );
}

class _BookingForSheet extends StatefulWidget {
  final BookingFor current;
  final String? riderPhone;
  const _BookingForSheet({required this.current, this.riderPhone});

  @override
  State<_BookingForSheet> createState() => _BookingForSheetState();
}

class _BookingForSheetState extends State<_BookingForSheet> {
  late bool _other = widget.current.isOther;
  late final _name = TextEditingController(text: widget.current.name ?? '');
  late final _phone = TextEditingController(text: widget.current.phone ?? '');
  List<BookingFor> _recent = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    RecentPassengers.load().then((r) {
      if (mounted) setState(() => _recent = r);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _done() {
    if (!_other) {
      Navigator.pop(context, const BookingFor.self());
      return;
    }
    final err = validatePassenger(_name.text, _phone.text, riderPhone: widget.riderPhone);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    final p = BookingFor.other(_name.text.trim(), indianMobile(_phone.text)!);
    RecentPassengers.remember(p);
    Navigator.pop(context, p);
  }

  Widget _option({required bool other, required IconData icon, required String title, required String sub}) {
    final sel = _other == other;
    return InkWell(
      key: ValueKey(other ? 'booking-for-other' : 'booking-for-self'),
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() { _other = other; _error = null; }),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: sel ? RideUi.ink(context) : RideUi.divider(context), width: sel ? 1.6 : 1),
        ),
        child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(color: RideUi.tile(context), shape: BoxShape.circle),
            child: Icon(icon, size: 19, color: RideUi.ink(context)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: RideUi.body(context, size: 15, weight: FontWeight.w800)),
            Text(sub, style: RideUi.caption(context, size: 12)),
          ])),
          Icon(sel ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              color: sel ? RideUi.ink(context) : RideUi.muted(context)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 10,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SheetHandle(bottom: 14),
          Text("Who's riding?", style: RideUi.title(context, size: 20)),
          const SizedBox(height: 14),
          _option(other: false, icon: Icons.person_rounded, title: 'Myself', sub: 'The ride is for you'),
          const SizedBox(height: 10),
          _option(other: true, icon: Icons.people_alt_rounded, title: 'Someone else',
              sub: 'The driver gets their name and number'),
          if (_other) ...[
            if (_recent.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('RECENT', style: RideUi.caption(context, size: 11).copyWith(letterSpacing: 1.2, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final r in _recent)
                  ActionChip(
                    avatar: const Icon(Icons.history_rounded, size: 16),
                    label: Text(r.name!),
                    onPressed: () => setState(() {
                      _name.text = r.name!;
                      _phone.text = r.phone!;
                      _error = null;
                    }),
                  ),
              ]),
            ],
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('passenger-name'),
              controller: _name,
              onChanged: (_) { if (_error != null) setState(() => _error = null); },
              textCapitalization: TextCapitalization.words,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'Passenger name', counterText: '',
                  prefixIcon: Icon(Icons.badge_outlined)),
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('passenger-phone'),
              controller: _phone,
              onChanged: (_) { if (_error != null) setState(() => _error = null); },
              keyboardType: TextInputType.phone,
              inputFormatters: [IndianPhoneInputFormatter()],
              decoration: const InputDecoration(labelText: 'Passenger mobile', prefixText: '+91 ',
                  prefixIcon: Icon(Icons.phone_outlined)),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              key: const ValueKey('booking-for-done'),
              onPressed: _done,
              child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
      ),
    );
  }
}
