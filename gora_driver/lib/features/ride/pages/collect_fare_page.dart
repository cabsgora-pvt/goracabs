import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../providers/driver_provider.dart';

// Shown when the driver ends a CASH ride: rider scans the driver's UPI QR to
// pay 100% directly, then the driver taps "Collect Fare" to complete the ride.
// Returns true via Navigator.pop when the driver confirms collection.
class CollectFarePage extends StatefulWidget {
  final double amount;
  const CollectFarePage({super.key, required this.amount});
  @override
  State<CollectFarePage> createState() => _CollectFarePageState();
}

class _CollectFarePageState extends State<CollectFarePage> {
  String _upiId = '';
  String _name = 'Driver';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dp = context.read<DriverProvider>();
    _name = dp.name.isNotEmpty ? dp.name : 'Driver';
    final prefs = await SharedPreferences.getInstance();
    var upi = prefs.getString('driver_upi') ?? '';
    if (upi.isEmpty) {
      // Default to a phone-based UPI handle (driver can change it)
      final phone = dp.phone.replaceAll(RegExp(r'[^0-9]'), '');
      upi = phone.isNotEmpty ? '$phone@ibl' : '';
    }
    if (mounted) setState(() => _upiId = upi);
  }

  Future<void> _changeQr() async {
    final ctrl = TextEditingController(text: _upiId);
    final saved = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Your UPI ID'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'e.g. name@okhdfcbank')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (saved == null || saved.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('driver_upi', saved);
    if (mounted) setState(() => _upiId = saved);
  }

  String get _upiUri {
    final amt = widget.amount.toStringAsFixed(0);
    return 'upi://pay?pa=$_upiId&pn=${Uri.encodeComponent(_name)}&am=$amt&cu=INR';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0.5, foregroundColor: Colors.black,
        title: const Text('Payments', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.headset_mic_outlined, size: 18, color: Colors.black),
              label: const Text('Help', style: TextStyle(color: Colors.black)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFDDDDDD)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
            ),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const SizedBox(height: 12),
        const Center(child: Text('Estimated Order Fare', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
        const SizedBox(height: 8),
        Center(child: Text('₹${widget.amount.toStringAsFixed(1)}', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: AppColors.green))),
        const SizedBox(height: 24),
        // QR card
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: const Color(0xFF1C2233), borderRadius: BorderRadius.circular(20)),
          child: Column(children: [
            const Text('Scan QR', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text('Pay 100% to me in my account', textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: _upiId.isEmpty
                  ? const SizedBox(width: 200, height: 200, child: Center(child: Text('Set your UPI ID', style: TextStyle(color: Colors.black54))))
                  : QrImageView(data: _upiUri, size: 200, version: QrVersions.auto),
            ),
            const SizedBox(height: 16),
            Text(_upiId.isEmpty ? '—' : _upiId, style: const TextStyle(color: Colors.white70, fontSize: 15)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _changeQr,
                icon: const Icon(Icons.qr_code_2, color: Colors.white, size: 18),
                label: const Text('Change QR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white54), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 30),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context, true),
            style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.grey[300]!), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
            child: const Text('Collect Fare', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 16),
      ]),
    );
  }
}
