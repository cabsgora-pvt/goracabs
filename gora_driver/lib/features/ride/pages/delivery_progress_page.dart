import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../config/app_config.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/models.dart';
import '../../../services/driver_api_service.dart';
import 'invoice_page.dart';

// Delivery flow after pickup-OTP start: collect from sender → deliver to receiver (drop OTP).
class DeliveryProgressPage extends StatefulWidget {
  static const route = '/delivery-progress';
  final RideRequestModel ride;
  const DeliveryProgressPage({super.key, required this.ride});
  @override
  State<DeliveryProgressPage> createState() => _DeliveryProgressPageState();
}

class _DeliveryProgressPageState extends State<DeliveryProgressPage> {
  bool _collected = false;
  bool _busy = false;
  String? _proofPhoto; // full url of captured proof
  final _picker = ImagePicker();

  Future<void> _markCollected() async {
    setState(() => _busy = true);
    await DriverApiService.deliveryAction(widget.ride.id, {'action': 'collected'});
    if (mounted) setState(() { _collected = true; _busy = false; });
  }

  Future<void> _captureProof() async {
    final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 60);
    if (x == null) return;
    setState(() => _busy = true);
    final url = await DriverApiService.uploadFile(x);
    if (mounted) setState(() { _proofPhoto = url; _busy = false; });
  }

  Future<void> _deliver() async {
    if (_proofPhoto == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Capture proof-of-delivery photo first')));
      return;
    }
    final ctrl = TextEditingController();
    final otp = await showDialog<String>(context: context, builder: (_) => AlertDialog(
      title: const Text('Enter Delivery OTP', style: TextStyle(fontWeight: FontWeight.w700)),
      content: TextField(controller: ctrl, keyboardType: TextInputType.number, maxLength: 4,
        decoration: const InputDecoration(labelText: 'OTP from Receiver', hintText: 'e.g. 4821'),
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 8)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(_), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(_, ctrl.text.trim()), child: const Text('Deliver')),
      ]));
    if (otp == null || otp.isEmpty) return;
    setState(() => _busy = true);
    final res = await DriverApiService.deliveryAction(widget.ride.id, {'action': 'deliver', 'dropOtp': otp, 'proofPhoto': _proofPhoto});
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['error'].toString()), backgroundColor: AppColors.red));
      return;
    }
    Navigator.pushReplacementNamed(context, InvoicePage.route, arguments: widget.ride);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.ride;
    return Scaffold(
      appBar: blueAppBar('Parcel Delivery'),
      backgroundColor: AppColors.cardBg,
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // COD banner
        if (r.codAmount > 0) Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.orange)),
          child: Row(children: [const Icon(Icons.payments, color: AppColors.orange), const SizedBox(width: 10),
            Expanded(child: Text('COLLECT ₹${r.codAmount.toStringAsFixed(0)} CASH from receiver', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.orange)))])),
        _card('Parcel', [
          _line(Icons.inventory_2, 'Item', r.itemType.isNotEmpty ? r.itemType : 'Parcel'),
          if (r.weightKg > 0) _line(Icons.fitness_center, 'Weight', '${r.weightKg.toStringAsFixed(0)} kg'),
          if (r.packageSize.isNotEmpty) _line(Icons.straighten, 'Size', r.packageSize),
          if (r.isFragile) _line(Icons.warning_amber, 'Care', 'FRAGILE — handle carefully'),
        ]),
        // Sender's parcel photos
        if (r.parcelPhotos.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: SizedBox(height: 72,
          child: ListView(scrollDirection: Axis.horizontal, children: r.parcelPhotos.map((u) => Container(width: 72, height: 72, margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), image: DecorationImage(image: NetworkImage(AppConfig.imageUrl(u)), fit: BoxFit.cover)))).toList()))),
        const SizedBox(height: 12),
        _card('Sender', [
          _line(Icons.person_outline, 'Name', r.senderName.isNotEmpty ? r.senderName : r.userName),
          _line(Icons.phone, 'Phone', r.senderPhone.isNotEmpty ? r.senderPhone : r.userPhone),
          _line(Icons.radio_button_checked, 'Pickup', r.pickupAddress),
        ]),
        const SizedBox(height: 12),
        _card('Receiver', [
          _line(Icons.person, 'Name', r.receiverName.isNotEmpty ? r.receiverName : '—'),
          _line(Icons.phone, 'Phone', r.receiverPhone.isNotEmpty ? r.receiverPhone : '—'),
          _line(Icons.location_on, 'Drop', r.dropAddress),
        ]),
        const SizedBox(height: 16),
        if (!_collected)
          PrimaryButton(label: _busy ? 'Saving...' : '📦 Parcel Collected from Sender', onTap: _busy ? null : _markCollected)
        else ...[
          // Proof-of-delivery photo
          OutlinedButton.icon(onPressed: _busy ? null : _captureProof,
            icon: Icon(_proofPhoto != null ? Icons.check_circle : Icons.camera_alt, color: _proofPhoto != null ? AppColors.green : AppColors.primary),
            label: Text(_proofPhoto != null ? 'Proof photo captured' : 'Capture proof-of-delivery photo', style: TextStyle(color: _proofPhoto != null ? AppColors.green : AppColors.primary)),
            style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48), side: BorderSide(color: _proofPhoto != null ? AppColors.green : AppColors.primary))),
          if (_proofPhoto != null) Padding(padding: const EdgeInsets.only(top: 8), child: ClipRRect(borderRadius: BorderRadius.circular(8),
            child: Image.network(_proofPhoto!, height: 120, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()))),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.green, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 52)),
            onPressed: _busy ? null : _deliver,
            child: Text(_busy ? 'Verifying...' : '✅ Delivered — Enter Receiver OTP', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)))),
        ],
      ]),
    );
  }

  Widget _card(String title, List<Widget> rows) => Container(
    width: double.infinity, padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.teal)),
      const SizedBox(height: 10), ...rows,
    ]));

  Widget _line(IconData i, String l, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [Icon(i, size: 16, color: AppColors.textGrey), const SizedBox(width: 8),
      SizedBox(width: 60, child: Text(l, style: const TextStyle(fontSize: 12, color: AppColors.textGrey))),
      Expanded(child: Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark), maxLines: 2))]));
}
