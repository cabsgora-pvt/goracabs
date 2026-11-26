import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../services/driver_api_service.dart';
import '../../../widgets/captain_ui/captain_ui.dart';

/// 20 Nov 2026 — '' when [iso] is not a date.
String shortDate(Object? iso) {
  final t = DateTime.tryParse((iso ?? '').toString())?.toLocal();
  return t == null ? '' : DateFormat('d MMM yyyy').format(t);
}

// The driver's zone: where it is now, auto-follow by location, a zone change
// request for the admin to approve, and the recent moves.
class ZonePage extends StatefulWidget {
  static const route = '/zone';
  const ZonePage({super.key});
  @override
  State<ZonePage> createState() => _ZonePageState();
}

class _ZonePageState extends State<ZonePage> {
  Map<String, dynamic>? _info;
  String? _error;
  bool _loading = true, _savingAuto = false, _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    Map<String, dynamic> res;
    try {
      res = await DriverApiService.getMyZone();
    } catch (_) {
      res = {'error': 'Could not reach the server. Check your connection.'};
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['error'] != null) {
        _error = res['error'].toString();
      } else {
        _info = res;
        _error = null;
      }
    });
  }

  void _snack(String text, {Color? color}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: color));

  /// Turns automatic zone OFF — the only way a driver may change it. Turning
  /// it on is for an admin (PUT zoneAuto:true is refused 403
  /// ZONE_AUTO_ADMIN_ONLY), so the app never offers it.
  Future<void> _turnAutoOff() async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Turn off automatic zone?'),
      content: const Text('Your zone will stay as it is. Only support can turn automatic zone on again — '
          'ask for a zone change if you move cities.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep it')),
        ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('Turn off')),
      ],
    ));
    if (ok != true || !mounted) return;
    setState(() => _savingAuto = true);
    Map<String, dynamic> res;
    try {
      res = await DriverApiService.setZoneAuto(false);
    } catch (_) {
      res = {'error': 'Could not reach the server'};
    }
    if (!mounted) return;
    setState(() {
      _savingAuto = false;
      if (res['error'] == null) _info?['zoneAuto'] = res['zoneAuto'] == true;
    });
    if (res['error'] != null) {
      _snack('Not saved: ${res['error']}', color: AppColors.red);
    } else {
      _snack('Automatic zone change turned off', color: AppColors.green);
    }
  }

  Future<void> _requestChange() async {
    final zones = ((_info?['zones'] as List?) ?? const [])
        .whereType<Map>()
        .map((z) => Map<String, dynamic>.from(z))
        .where((z) => (z['id'] ?? '').toString() != (_info?['zoneId'] ?? '').toString())
        .toList();
    if (zones.isEmpty) {
      _snack('No other zone is available right now');
      return;
    }
    final picked = await showModalBottomSheet<({String id, String note})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Cap.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => _ZonePickerSheet(zones: zones),
    );
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    Map<String, dynamic> res;
    try {
      res = await DriverApiService.createAccountRequest(
          {'kind': 'zone_change', 'toZoneId': picked.id, 'note': picked.note});
    } catch (_) {
      res = {'error': 'Could not reach the server'};
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['error'] != null) {
      _snack(res['error'].toString(), color: AppColors.red);
      return;
    }
    _snack('Request sent. The admin will review it.', color: AppColors.green);
    _load();
  }

  Future<void> _withdraw(String id) async {
    setState(() => _busy = true);
    Map<String, dynamic> res;
    try {
      res = await DriverApiService.withdrawAccountRequest(id);
    } catch (_) {
      res = {'error': 'Could not reach the server'};
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['error'] != null) {
      _snack(res['error'].toString(), color: AppColors.red);
      return;
    }
    _snack('Request withdrawn');
    _load();
  }

  static String _byLabel(String by) {
    if (by == 'auto') return 'Changed automatically by your location';
    if (by.startsWith('request')) return 'Your request, approved by admin';
    if (by.startsWith('admin')) return 'Changed by admin';
    return 'Changed';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: blueAppBar('My zone'),
      backgroundColor: Cap.tile,
      body: _loading
          ? const AppLoader()
          : _info == null
              ? CapEmpty(
                  icon: Icons.cloud_off_rounded,
                  title: 'Could not load your zone',
                  message: _error,
                  action: SizedBox(
                    width: 180,
                    child: CapButton(label: 'Try again', height: 46, onPressed: () {
                      setState(() => _loading = true);
                      _load();
                    }),
                  ),
                )
              : RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    final info = _info!;
    final zoneName = (info['zoneName'] ?? '').toString();
    final auto = info['zoneAuto'] == true;
    final pending = info['pendingRequest'] is Map ? Map<String, dynamic>.from(info['pendingRequest'] as Map) : null;
    final history = ((info['history'] as List?) ?? const []).whereType<Map>().toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        // Current zone
        CapCard(
          child: Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: Cap.accent.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14)),
              child: Icon(Icons.location_city_rounded, color: Cap.accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Current zone', style: Cap.caption(size: 12.5)),
                const SizedBox(height: 2),
                Text(zoneName.isNotEmpty ? zoneName : 'Not assigned yet',
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: Cap.title(size: 19)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 12),

        // Automatic zone: set by an admin only. Shown when it is on, as
        // information, with a way to turn it off — never a switch to turn it on.
        if (auto)
          CapCard(
            key: const ValueKey('zone_auto_info'),
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(children: [
              Icon(Icons.my_location_rounded, color: Cap.ink, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Automatic zone is on', style: Cap.body(size: 14, weight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text('Managed by admin — when you go online inside another zone, you move to that zone',
                      style: Cap.caption(size: 12)),
                ]),
              ),
              TextButton(
                onPressed: _savingAuto ? null : _turnAutoOff,
                child: const Text('Turn off'),
              ),
            ]),
          ),

        // Pending request
        if (pending != null) ...[
          const SizedBox(height: 12),
          CapBanner(
            icon: Icons.schedule_rounded,
            tone: CapTone.warning,
            title: 'Zone change requested',
            text: 'To ${(pending['toZoneName'] ?? '').toString().isNotEmpty ? pending['toZoneName'] : 'a new zone'}'
                '${shortDate(pending['createdAt']).isNotEmpty ? ' · ${shortDate(pending['createdAt'])}' : ''}'
                ' — waiting for admin approval',
            trailing: TextButton(
              onPressed: _busy ? null : () => _withdraw((pending['id'] ?? '').toString()),
              child: const Text('Withdraw'),
            ),
          ),
        ],
        const SizedBox(height: 16),
        CapButton(
          label: pending != null ? 'Request a different zone' : 'Request zone change',
          icon: Icons.swap_horiz_rounded,
          tone: CapButtonTone.outline,
          loading: _busy,
          onPressed: _requestChange,
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('The admin reviews every zone change request.', style: Cap.caption(size: 12)),
        ),

        // History
        const CapSectionTitle('Recent zone changes'),
        if (history.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('No zone changes yet', style: Cap.caption(size: 13)),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: Cap.surface,
              borderRadius: BorderRadius.circular(Cap.radius),
              border: Border.all(color: Cap.divider),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (var i = 0; i < history.length; i++) ...[
                if (i > 0) Container(height: 1, color: Cap.divider),
                _historyRow(Map<String, dynamic>.from(history[i])),
              ],
            ]),
          ),
      ],
    );
  }

  Widget _historyRow(Map<String, dynamic> h) {
    final from = (h['fromName'] ?? '').toString();
    final to = (h['toName'] ?? '').toString();
    final date = shortDate(h['at']);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.swap_horiz_rounded, size: 20, color: Cap.muted),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${from.isNotEmpty ? from : 'No zone'} → ${to.isNotEmpty ? to : 'No zone'}',
                maxLines: 2, overflow: TextOverflow.ellipsis, style: Cap.body(size: 13.5, weight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text([_byLabel((h['by'] ?? '').toString()), if (date.isNotEmpty) date].join(' · '),
                maxLines: 2, overflow: TextOverflow.ellipsis, style: Cap.caption(size: 12)),
          ]),
        ),
      ]),
    );
  }
}

/// Pick the zone to move to, plus an optional note for the admin.
class _ZonePickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> zones;
  const _ZonePickerSheet({required this.zones});
  @override
  State<_ZonePickerSheet> createState() => _ZonePickerSheetState();
}

class _ZonePickerSheetState extends State<_ZonePickerSheet> {
  String? _picked;
  final _note = TextEditingController();

  @override
  void dispose() { _note.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.85),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const CapSheetHandle(),
              const SizedBox(height: 12),
              Text('Request zone change', style: Cap.title(size: 19)),
              const SizedBox(height: 2),
              Text('Choose the zone you want to drive in', style: Cap.caption(size: 12.5)),
              const SizedBox(height: 10),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    RadioGroup<String>(
                      groupValue: _picked,
                      onChanged: (v) => setState(() => _picked = v),
                      child: Column(children: [
                        for (final z in widget.zones)
                          RadioListTile<String>(
                            value: (z['id'] ?? '').toString(),
                            contentPadding: EdgeInsets.zero,
                            activeColor: Cap.accent,
                            title: Text((z['name'] ?? '').toString(),
                                maxLines: 2, overflow: TextOverflow.ellipsis, style: Cap.body(size: 14.5)),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _note,
                      maxLength: 500,
                      maxLines: 2,
                      decoration: Cap.input(hint: 'Note for the admin (optional)'),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              CapButton(
                label: 'Send request',
                onPressed: _picked == null
                    ? null
                    : () => Navigator.pop(context, (id: _picked!, note: _note.text.trim())),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
