import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../providers/driver_provider.dart';
import '../../../services/driver_api_service.dart';
import '../../account/pages/support_page.dart';

/// A UPI ID: handle@provider (the server checks the same rule).
final _upiRe = RegExp(r'^[a-zA-Z0-9.\-_]{2,256}@[a-zA-Z][a-zA-Z0-9.\-]{1,63}$');

/// [v] trimmed and lower-cased when it is a UPI ID, else null.
String? normaliseUpiId(String v) {
  final s = v.trim().toLowerCase();
  return _upiRe.hasMatch(s) ? s : null;
}

/// The driver's UPI ID as the server holds it (profile `upiId`), or ''.
String upiIdOf(Map<String, dynamic>? driver) => (driver?['upiId'] ?? '').toString().trim();

/// The pay-me link in the QR: the driver's own UPI ID, name and the amount.
String upiPayUri(String upiId, String name, num amount) =>
    'upi://pay?pa=${Uri.encodeComponent(upiId)}&pn=${Uri.encodeComponent(name)}&am=${amount.toStringAsFixed(0)}&cu=INR';

// Shown when the driver ends a CASH ride: rider scans the driver's UPI QR to
// pay 100% directly, then the driver taps "Collect Fare" to complete the ride.
// Returns true via Navigator.pop when the driver confirms collection.
class CollectFarePage extends StatefulWidget {
  final double amount;
  /// What is being collected. The toll on a prepaid outstation trip is
  /// collected on this screen too, and is not a fare.
  final String title;
  const CollectFarePage({super.key, required this.amount, this.title = 'Estimated Order Fare'});
  @override
  State<CollectFarePage> createState() => _CollectFarePageState();
}

class _CollectFarePageState extends State<CollectFarePage> {
  // Only a UPI ID the server holds for this driver is put in the QR. It used
  // to be guessed as <phone>@ibl — a QR that sent riders' money to whoever
  // owned that handle, or nowhere.
  String _upiId = '';
  String _name = 'Driver';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    DriverProvider? dp;
    try { dp = context.read<DriverProvider>(); } catch (_) {}
    _name = (dp?.name ?? '').isNotEmpty ? dp!.name : 'Driver';
    final cached = upiIdOf(dp?.data);
    if (cached.isNotEmpty) { _upiId = cached; _loading = false; }
    try {
      final res = await DriverApiService.getProfile();
      final d = res['driver'];
      if (d is Map) {
        final driver = Map<String, dynamic>.from(d);
        dp?.setData(driver);
        if (mounted) setState(() => _upiId = upiIdOf(driver));
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _setUpi() async {
    final saved = await showDialog<String>(
      context: context,
      builder: (_) => UpiIdDialog(initial: _upiId),
    );
    if (saved == null || !mounted) return;
    setState(() => _upiId = saved);
    try {
      final dp = context.read<DriverProvider>();
      dp.setData({...?dp.data, 'upiId': saved});
    } catch (_) {}
  }

  /// "₹40", not "₹40.0"; paise only when there are any ("₹40.50").
  static String _money(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0, scrolledUnderElevation: 0, foregroundColor: Colors.black,
        title: const Text('Payments', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.black)),
        bottom: const PreferredSize(preferredSize: Size.fromHeight(1), child: Divider(height: 1, color: Color(0xFFE5E7EB))),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: OutlinedButton.icon(
              onPressed: () => Navigator.pushNamed(context, SupportPage.route),
              icon: const Icon(Icons.headset_mic_outlined, size: 18, color: Colors.black),
              label: const Text('Help', style: TextStyle(color: Colors.black)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFDDDDDD)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
            ),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const SizedBox(height: 12),
        Center(child: Text(widget.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF6B7280)))),
        const SizedBox(height: 6),
        Center(child: Text('₹${_money(widget.amount)}', style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: Color(0xFF111111), letterSpacing: -0.5))),
        const SizedBox(height: 24),
        // QR card
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(20)),
          child: Column(children: [
            const Text('Scan QR', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(_upiId.isEmpty ? 'Set your UPI ID to show a QR riders can pay you with' : 'Pay 100% to me in my account',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: _upiId.isEmpty
                  ? SizedBox(width: 200, height: 200, child: Center(child: _loading
                      ? const CircularProgressIndicator(strokeWidth: 2.4)
                      : const Text('Set your UPI ID', key: ValueKey('upi_missing'),
                          style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700))))
                  : QrImageView(key: const ValueKey('upi_qr'),
                      data: upiPayUri(_upiId, _name, widget.amount), size: 200, version: QrVersions.auto),
            ),
            const SizedBox(height: 16),
            Text(_upiId.isEmpty ? 'Or collect the cash in hand' : _upiId,
                style: const TextStyle(color: Colors.white70, fontSize: 15)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _loading ? null : _setUpi,
                icon: const Icon(Icons.qr_code_2, color: Colors.white, size: 18),
                label: Text(_upiId.isEmpty ? 'Set UPI ID' : 'Change UPI ID',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white54), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 30),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.green, foregroundColor: Colors.white, elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: const Text('Collect Fare', style: TextStyle(color: Colors.white, fontSize: 16.5, fontWeight: FontWeight.w800)),
          ),
        ),
        const SizedBox(height: 16),
      ]),
    );
  }
}

/// Asks for the driver's UPI ID and saves it on the server
/// (PUT /auth/driver/banks {upiId}). Pops with the saved ID, or null.
class UpiIdDialog extends StatefulWidget {
  final String initial;
  const UpiIdDialog({super.key, this.initial = ''});
  @override
  State<UpiIdDialog> createState() => _UpiIdDialogState();
}

class _UpiIdDialogState extends State<UpiIdDialog> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.initial);
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final upi = normaliseUpiId(_ctrl.text);
    if (upi == null) {
      setState(() => _error = 'Enter your UPI ID, like name@okhdfcbank');
      return;
    }
    setState(() { _saving = true; _error = null; });
    Map<String, dynamic> res;
    try {
      res = await DriverApiService.saveUpiId(upi);
    } catch (_) {
      res = const {'error': 'Could not reach Gora. Check your internet and try again.'};
    }
    if (!mounted) return;
    if (res['error'] != null) {
      setState(() { _saving = false; _error = res['error'].toString(); });
      return;
    }
    Navigator.pop(context, (res['upiId'] ?? upi).toString());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Your UPI ID'),
    content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Riders scan your QR to pay this UPI ID. Check it carefully — '
          'it is where cash-ride payments go.', style: TextStyle(fontSize: 13)),
      const SizedBox(height: 10),
      TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        decoration: InputDecoration(hintText: 'e.g. name@okhdfcbank', errorText: _error),
        onSubmitted: (_) => _save(),
      ),
    ]),
    actions: [
      TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
      ElevatedButton(
        onPressed: _saving ? null : _save,
        child: _saving
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('Save'),
      ),
    ],
  );
}
