import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/ride_ui/ride_ui.dart';

const _red = Color(0xFFD32F2F);

/// Asks Gora to delete the rider's account. Nothing is deleted here: the
/// request goes to the admin, who reviews it. Once approved, the next profile
/// call answers {accountDeleted: true} and the app signs the rider out.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});
  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _loadError;
  List<String> _reasons = const [];
  List<Map<String, dynamic>> _requests = const [];
  String? _reason;
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    Map<String, dynamic> res;
    try {
      res = await ApiService.getAccountRequests();
    } catch (_) {
      res = const {'error': 'Could not reach Gora. Check your connection and try again.'};
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['reasons'] is List || res['requests'] is List) {
        _loadError = null;
        _reasons = ((res['reasons'] as List?) ?? const []).map((e) => e.toString()).toList();
        _requests = ((res['requests'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .where((r) => r['kind'] == 'delete')
            .toList();
        if (_reason != null && !_reasons.contains(_reason)) _reason = null;
      } else {
        _loadError = (res['error'] ?? 'Could not load this page').toString();
      }
    });
  }

  Map<String, dynamic>? get _pending {
    for (final r in _requests) {
      if (r['status'] == 'pending') return r;
    }
    return null;
  }

  /// The latest decided request, shown when it was declined so the rider
  /// knows what happened to it.
  Map<String, dynamic>? get _lastRejected {
    if (_requests.isEmpty) return null;
    final r = _requests.first; // newest first
    return r['status'] == 'rejected' ? r : null;
  }

  static String _date(Object? iso) {
    final t = iso == null ? null : DateTime.tryParse(iso.toString())?.toLocal();
    if (t == null) return '';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${t.day} ${months[t.month - 1]} ${t.year}';
  }

  void _snack(String msg, {required bool ok}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: ok ? Colors.green.shade700 : Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null || _busy) return;
    FocusScope.of(context).unfocus();
    final yes = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Delete your account?', style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text(
          'Your request goes to our team for review. Once it is approved your account is closed and '
          'you are signed out of the app.\n\nYour ride and payment history is kept for our records.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(dctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white),
            child: const Text('Yes, request deletion'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    Map<String, dynamic> res;
    try {
      res = await ApiService.requestAccountDeletion(reason, _note.text.trim());
    } catch (_) {
      res = const {'error': 'Could not reach Gora. Check your connection and try again.'};
    }
    if (!mounted) return;
    if (res['success'] == true && res['request'] is Map) {
      final req = Map<String, dynamic>.from(res['request'] as Map);
      setState(() {
        _busy = false;
        _requests = [req, ..._requests.where((r) => r['id'] != req['id'])];
        _note.clear();
        _reason = null;
      });
      _snack('Deletion request sent', ok: true);
    } else {
      setState(() => _busy = false);
      _snack((res['error'] ?? 'Could not send the request. Please try again.').toString(), ok: false);
    }
  }

  Future<void> _withdraw(String id) async {
    if (_busy) return;
    setState(() => _busy = true);
    Map<String, dynamic> res;
    try {
      res = await ApiService.withdrawAccountRequest(id);
    } catch (_) {
      res = const {'error': 'Could not reach Gora. Check your connection and try again.'};
    }
    if (!mounted) return;
    if (res['success'] == true) {
      setState(() {
        _busy = false;
        _requests = _requests.map((r) => r['id'] == id ? {...r, 'status': 'cancelled'} : r).toList();
      });
      _snack('Request withdrawn. Your account stays active.', ok: true);
    } else {
      setState(() => _busy = false);
      _snack((res['error'] ?? 'Could not withdraw the request. Please try again.').toString(), ok: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    final canSubmit = !_loading && _loadError == null && pending == null;
    return Scaffold(
      backgroundColor: RideUi.surface(context),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: RideUi.surface(context),
        title: Text('Delete account', style: RideUi.title(context, size: 18)),
        centerTitle: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(RideUi.gutter, 4, RideUi.gutter, 24),
                children: [
                  if (_loadError != null)
                    NoticeRow(_loadError!, tone: NoticeTone.warning, onRetry: () {
                      setState(() => _loading = true);
                      _load();
                    })
                  else if (pending != null)
                    ..._pendingView(pending)
                  else
                    ..._formView(),
                ],
              ),
            ),
      bottomNavigationBar: canSubmit
          ? Padding(
              // Above the keyboard while typing the note.
              padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
              child: _ctaBar(),
            )
          : null,
    );
  }

  // ── A request is waiting for the admin ──────────────────────────────────
  List<Widget> _pendingView(Map<String, dynamic> r) {
    final on = _date(r['createdAt']);
    final reason = (r['reason'] ?? '').toString();
    return [
      Container(
        key: const ValueKey('delete-pending'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFB45309).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFB45309).withValues(alpha: 0.35)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.hourglass_top_rounded, color: Color(0xFFB45309), size: 22),
            const SizedBox(width: 8),
            Expanded(child: Text('Deletion requested', style: RideUi.title(context, size: 16))),
          ]),
          const SizedBox(height: 8),
          Text(
            on.isNotEmpty
                ? 'Deletion requested on $on — our team will review it'
                : 'Deletion requested — our team will review it',
            style: RideUi.body(context, size: 14, weight: FontWeight.w600).copyWith(height: 1.35),
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Reason: $reason', style: RideUi.caption(context, size: 13)),
          ],
          const SizedBox(height: 10),
          Text(
            'You can keep using Gora until then. Changed your mind? Withdraw the request and your account stays as it is.',
            style: RideUi.caption(context, size: 12.5).copyWith(height: 1.35),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _busy ? null : () => _withdraw((r['id'] ?? '').toString()),
          icon: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.undo_rounded, size: 18),
          label: const Text('Withdraw request'),
          style: OutlinedButton.styleFrom(
            foregroundColor: RideUi.accent(context),
            padding: const EdgeInsets.symmetric(vertical: 13),
            side: BorderSide(color: RideUi.accent(context).withValues(alpha: 0.5)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
        ),
      ),
      const SizedBox(height: 20),
      _whatHappens(),
    ];
  }

  // ── Choose a reason and send the request ────────────────────────────────
  List<Widget> _formView() {
    final rejected = _lastRejected;
    return [
      Text('We are sorry to see you go', style: RideUi.title(context, size: 20)),
      const SizedBox(height: 6),
      Text('Tell us why you want to delete your account. Our team reviews every request.',
          style: RideUi.caption(context, size: 13.5).copyWith(height: 1.35)),
      if (rejected != null) ...[
        const SizedBox(height: 14),
        NoticeRow(
          'Your request of ${_date(rejected['createdAt'])} was declined'
          '${(rejected['adminNote'] ?? '').toString().isNotEmpty ? ': ${rejected['adminNote']}' : '.'}',
          tone: NoticeTone.warning,
        ),
      ],
      const SizedBox(height: 20),
      const RideSectionTitle('Why are you leaving?', size: 16),
      const SizedBox(height: 10),
      RideTile(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(children: [
          for (var i = 0; i < _reasons.length; i++) ...[
            if (i > 0) const RideDivider(indent: 48),
            _reasonRow(_reasons[i]),
          ],
        ]),
      ),
      const SizedBox(height: 18),
      Text('Anything else? (optional)', style: RideUi.caption(context, size: 12.5)),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: RideUi.fieldBox(context),
        child: TextField(
          controller: _note,
          enabled: !_busy,
          minLines: 3,
          maxLines: 5,
          maxLength: 500,
          textCapitalization: TextCapitalization.sentences,
          decoration: RideUi.bareInput(context, 'Tell us more so we can improve', vertical: 10)
              .copyWith(counterText: ''),
          style: RideUi.body(context, size: 14.5, weight: FontWeight.w500),
        ),
      ),
      const SizedBox(height: 20),
      _whatHappens(),
    ];
  }

  Widget _reasonRow(String reason) {
    final selected = _reason == reason;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _busy ? null : () => setState(() => _reason = reason),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
          child: Row(children: [
            Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                size: 22, color: selected ? RideUi.accent(context) : RideUi.muted(context)),
            const SizedBox(width: 14),
            Expanded(
              child: Text(reason,
                  style: RideUi.body(context, size: 14.5, weight: selected ? FontWeight.w800 : FontWeight.w600)),
            ),
          ]),
        ),
      ),
    );
  }

  // On the plain surface: InfoLine's grey icon circles vanish on a grey tile.
  Widget _whatHappens() => Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('What happens next', style: RideUi.body(context, size: 15, weight: FontWeight.w800)),
          const SizedBox(height: 6),
          const InfoLine(Icons.fact_check_outlined, 'Our team reviews your request'),
          const InfoLine(Icons.logout_rounded, 'Once approved, your account is closed and you are signed out'),
          const InfoLine(Icons.receipt_long_outlined, 'Your ride and payment history is kept for our records'),
          const InfoLine(Icons.undo_rounded, 'You can withdraw the request while it is under review'),
        ]),
      );

  Widget _ctaBar() => Container(
        decoration: BoxDecoration(
          color: RideUi.surface(context),
          border: Border(top: BorderSide(color: RideUi.divider(context))),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: PrimaryRideButton(
              label: _busy
                  ? 'Sending…'
                  : (_reason == null ? 'Choose a reason' : 'Request account deletion'),
              icon: Icons.delete_outline_rounded,
              color: _red,
              onPressed: _busy || _reason == null ? null : _submit,
            ),
          ),
        ),
      );
}
