import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../services/driver_api_service.dart';
import '../../../services/location_service.dart';

// Emergency contacts.
//
// This screen used to render mockSOSContacts — invented names and numbers on a
// safety screen — and its "SEND SOS ALERT" button only showed a snackbar. Both
// are now real: contacts come from /auth/driver/sos-contacts (admin-provided
// control-room numbers plus the driver's own), and the alert posts to
// /support/sos-alert with the driver's live position, the same endpoint the
// in-ride emergency screen uses.
class SosPage extends StatefulWidget {
  static const route = '/sos';
  const SosPage({super.key});
  @override
  State<SosPage> createState() => _SosPageState();
}

class _Contact {
  final String id, name, phone, relation;
  final bool editable;
  const _Contact({
    required this.id,
    required this.name,
    required this.phone,
    required this.relation,
    required this.editable,
  });
}

class _SosPageState extends State<SosPage> {
  List<_Contact> _contacts = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await DriverApiService.getSosContacts();
      final raw = (res['contacts'] as List?) ?? const [];
      if (!mounted) return;
      setState(() {
        _contacts = raw.map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          return _Contact(
            id: (m['id'] ?? '').toString(),
            name: (m['name'] ?? '').toString(),
            phone: (m['phone'] ?? '').toString(),
            relation: (m['relation'] ?? '').toString(),
            editable: m['editable'] == true,
          );
        }).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      // Never invent contacts here — an empty list with an error is safer than
      // showing numbers that will not be called.
      setState(() { _loading = false; _error = 'Could not load your emergency contacts'; });
    }
  }

  Future<void> _addContact() async {
    final name = TextEditingController(), phone = TextEditingController(), rel = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (dctx) => AlertDialog(
      title: const Text('Add SOS Contact', style: TextStyle(fontWeight: FontWeight.w700)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
        const SizedBox(height: 8),
        TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone'), keyboardType: TextInputType.phone),
        const SizedBox(height: 8),
        TextField(controller: rel, decoration: const InputDecoration(labelText: 'Relation')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('Add')),
      ],
    ));
    if (ok != true) return;
    if (name.text.trim().isEmpty || phone.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Name and phone are required')));
      }
      return;
    }
    final res = await DriverApiService.addSosContact({
      'name': name.text.trim(), 'phone': phone.text.trim(), 'relation': rel.text.trim(),
    });
    if (!mounted) return;
    if (res['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['error'].toString()), backgroundColor: AppColors.red));
      return;
    }
    _load();
  }

  Future<void> _delete(_Contact c) async {
    final res = await DriverApiService.deleteSosContact(c.id);
    if (!mounted) return;
    if (res['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['error'].toString()), backgroundColor: AppColors.red));
      return;
    }
    setState(() => _contacts = _contacts.where((x) => x.id != c.id).toList());
  }

  Future<void> _sendAlert() async {
    if (_sending) return;
    final confirmed = await showDialog<bool>(context: context, builder: (dctx) => AlertDialog(
      title: const Text('Send SOS alert?', style: TextStyle(fontWeight: FontWeight.w700)),
      content: const Text('Your live location will be sent to the control room immediately.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.red, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(dctx, true),
          child: const Text('Send SOS'),
        ),
      ],
    ));
    if (confirmed != true) return;

    setState(() => _sending = true);
    final pos = await LocationService.getCurrentLocation();
    final res = await DriverApiService.sendSosAlert({
      'triggeredBy': 'driver',
      'lat': pos?.latitude,
      'lng': pos?.longitude,
    });
    if (!mounted) return;
    setState(() => _sending = false);
    final failed = res['error'] != null || res['success'] != true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(failed
          ? 'Could not send the alert — call 112 directly'
          : 'SOS alert sent. The control room has your location.'),
      backgroundColor: failed ? AppColors.red : AppColors.green,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: blueAppBar('SOS Contacts', actions: [
        IconButton(icon: const Icon(Icons.add, color: Colors.white), onPressed: _addContact),
      ]),
      backgroundColor: AppColors.cardBg,
      body: Column(children: [
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.red.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.red.withOpacity(0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.sos, color: AppColors.red, size: 28),
            const SizedBox(width: 12),
            Expanded(child: Text('In an emergency, press SOS to alert the control room with your live location.',
                style: TextStyle(fontSize: 13, color: AppColors.textDark))),
          ]),
        ),
        Expanded(child: _body()),
        Padding(
          padding: const EdgeInsets.all(20),
          child: ElevatedButton.icon(
            icon: _sending
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.sos, size: 22),
            label: Text(_sending ? 'SENDING…' : 'SEND SOS ALERT',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red, foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _sending ? null : _sendAlert,
          ),
        ),
      ]),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_error!, style: TextStyle(color: AppColors.textGrey)),
        const SizedBox(height: 10),
        OutlinedButton(onPressed: _load, child: const Text('Retry')),
      ]));
    }
    if (_contacts.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text('No emergency contacts yet. Tap + to add someone who should be called if you need help.',
            textAlign: TextAlign.center, style: TextStyle(color: AppColors.textGrey)),
      ));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _contacts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final c = _contacts[i];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
          ),
          child: Row(children: [
            CircleAvatar(
              backgroundColor: AppColors.red.withOpacity(0.12), radius: 22,
              child: Text(c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                  style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark)),
              Text([c.phone, if (c.relation.isNotEmpty) c.relation].join('  •  '),
                  style: TextStyle(fontSize: 12, color: AppColors.textGrey)),
            ])),
            if (c.editable)
              IconButton(icon: const Icon(Icons.delete_outline, color: AppColors.red), onPressed: () => _delete(c))
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('Gora', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textGrey)),
              ),
          ]),
        );
      },
    );
  }
}
