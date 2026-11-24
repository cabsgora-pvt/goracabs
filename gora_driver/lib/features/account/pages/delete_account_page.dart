import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../services/driver_api_service.dart';
import '../../../widgets/captain_ui/captain_ui.dart';
import 'zone_page.dart' show shortDate;

// Asks the admin to delete this account, with a reason. Nothing is deleted
// here: the admin reviews the request, and it can be withdrawn until then.
class DeleteAccountPage extends StatefulWidget {
  static const route = '/delete-account';
  const DeleteAccountPage({super.key});
  @override
  State<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends State<DeleteAccountPage> {
  // Used when the server sends no list.
  static const _fallbackReasons = ['I no longer need the app', 'Other'];

  List<String> _reasons = const [];
  Map<String, dynamic>? _pending; // open delete request, if any
  String? _reason, _error;
  final _note = TextEditingController();
  bool _loading = true, _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() { _note.dispose(); super.dispose(); }

  Future<void> _load() async {
    Map<String, dynamic> res;
    try {
      res = await DriverApiService.getAccountRequests();
    } catch (_) {
      res = {'error': 'Could not reach the server. Check your connection.'};
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = res['error']?.toString();
      if (_error != null) return;
      final reasons = ((res['reasons'] as List?) ?? const []).map((r) => r.toString()).where((r) => r.isNotEmpty).toList();
      _reasons = reasons.isNotEmpty ? reasons : _fallbackReasons;
      _pending = ((res['requests'] as List?) ?? const [])
          .whereType<Map>()
          .map((r) => Map<String, dynamic>.from(r))
          .where((r) => r['kind'] == 'delete' && r['status'] == 'pending')
          .firstOrNull;
    });
  }

  void _snack(String text, {Color? color}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: color));

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text('We will send your request to the admin. Your account is deleted only after '
            'they review and approve it. You can withdraw the request until then.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, request deletion', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    Map<String, dynamic> res;
    try {
      res = await DriverApiService.createAccountRequest({'kind': 'delete', 'reason': reason, 'note': _note.text.trim()});
    } catch (_) {
      res = {'error': 'Could not reach the server'};
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['error'] != null) {
      _snack(res['error'].toString(), color: AppColors.red);
      return;
    }
    _snack('Deletion requested. The admin will review it.', color: AppColors.green);
    if (res['request'] is Map) {
      setState(() => _pending = Map<String, dynamic>.from(res['request'] as Map));
    } else {
      _load();
    }
  }

  Future<void> _withdraw() async {
    final id = (_pending?['id'] ?? '').toString();
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
    _snack('Request withdrawn. Your account stays active.', color: AppColors.green);
    setState(() { _pending = null; _reason = null; _note.clear(); });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: blueAppBar('Delete account'),
      backgroundColor: Cap.tile,
      body: _loading
          ? const AppLoader()
          : _error != null
              ? CapEmpty(
                  icon: Icons.cloud_off_rounded,
                  title: 'Could not load',
                  message: _error,
                  action: SizedBox(
                    width: 180,
                    child: CapButton(label: 'Try again', height: 46, onPressed: () {
                      setState(() { _loading = true; _error = null; });
                      _load();
                    }),
                  ),
                )
              : _pending != null
                  ? _pendingView()
                  : _formView(),
    );
  }

  Widget _pendingView() {
    final date = shortDate(_pending!['createdAt']);
    return ListView(padding: const EdgeInsets.all(16), children: [
      CapBanner(
        icon: Icons.hourglass_top_rounded,
        tone: CapTone.warning,
        title: 'Deletion requested${date.isNotEmpty ? ' on $date' : ''} — waiting for admin',
        text: 'The admin reviews your request before the account is deleted. '
            'Changed your mind? Withdraw the request and your account stays as it is.',
      ),
      if ((_pending!['reason'] ?? '').toString().isNotEmpty) ...[
        const SizedBox(height: 12),
        CapCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Reason', style: Cap.caption(size: 12)),
            const SizedBox(height: 2),
            Text(_pending!['reason'].toString(), style: Cap.body(size: 14.5, weight: FontWeight.w700)),
          ]),
        ),
      ],
      const SizedBox(height: 20),
      CapButton(
        label: 'Withdraw request',
        icon: Icons.undo_rounded,
        tone: CapButtonTone.outline,
        loading: _busy,
        onPressed: _withdraw,
      ),
    ]);
  }

  Widget _formView() {
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 16), children: [
          const CapBanner(
            icon: Icons.info_outline_rounded,
            title: 'The admin reviews this request',
            text: 'Your account is not deleted straight away. Our team checks your request first, '
                'and you can withdraw it until then.',
          ),
          const CapSectionTitle('Why are you leaving?'),
          Container(
            decoration: BoxDecoration(
              color: Cap.surface,
              borderRadius: BorderRadius.circular(Cap.radius),
              border: Border.all(color: Cap.divider),
            ),
            child: RadioGroup<String>(
              groupValue: _reason,
              onChanged: (v) => setState(() => _reason = v),
              child: Column(children: [
                for (final r in _reasons)
                  RadioListTile<String>(
                    value: r,
                    activeColor: Cap.accent,
                    title: Text(r, style: Cap.body(size: 14.5)),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          const CapLabel('Anything else? (optional)'),
          TextField(
            controller: _note,
            maxLength: 500,
            maxLines: 3,
            decoration: Cap.input(hint: 'Tell us more'),
          ),
        ]),
      ),
      CapBottomBar(
        child: CapButton(
          label: 'Request account deletion',
          tone: CapButtonTone.danger,
          loading: _busy,
          onPressed: _reason == null ? null : _submit,
        ),
      ),
    ]);
  }
}
