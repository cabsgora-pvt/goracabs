import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../config/app_config.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/models.dart';
import '../../../services/driver_api_service.dart';
import '../../../services/location_service.dart';
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
  String? _signatureUrl;
  final _picker = ImagePicker();
  Timer? _ping;
  final List<Offset?> _sigPoints = [];

  // Open external Google Maps navigation to pickup (before collect) or drop (after)
  Future<void> _navigate() async {
    final r = widget.ride;
    final lat = _collected ? r.dropLat : r.pickupLat;
    final lng = _collected ? r.dropLng : r.pickupLng;
    final uri = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    final web = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    if (await canLaunchUrl(uri)) { await launchUrl(uri); }
    else { await launchUrl(web, mode: LaunchMode.externalApplication); }
  }

  // Capture receiver signature via a simple draw pad, upload as PNG
  Future<void> _captureSignature() async {
    _sigPoints.clear();
    final key = GlobalKey();
    await showDialog(context: context, builder: (dctx) => StatefulBuilder(builder: (dctx, setS) => AlertDialog(
      title: const Text('Receiver Signature'),
      content: RepaintBoundary(key: key,
        child: Container(width: 300, height: 200, color: Colors.grey[100],
          child: GestureDetector(
            onPanUpdate: (d) {
              final box = key.currentContext!.findRenderObject() as RenderBox;
              setS(() => _sigPoints.add(box.globalToLocal(d.globalPosition)));
            },
            onPanEnd: (_) => setS(() => _sigPoints.add(null)),
            child: CustomPaint(painter: _SigPainter(_sigPoints), size: const Size(300, 200)),
          ))),
      actions: [
        TextButton(onPressed: () => setS(() => _sigPoints.clear()), child: const Text('Clear')),
        ElevatedButton(onPressed: () async {
          final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final bd = await image.toByteData(format: ui.ImageByteFormat.png);
          Navigator.pop(dctx);
          if (bd == null) return;
          setState(() => _busy = true);
          final url = await DriverApiService.uploadBytes(bd.buffer.asUint8List(), 'signature.png');
          if (mounted) setState(() { _signatureUrl = url; _busy = false; });
        }, child: const Text('Save')),
      ])));
  }

  @override
  void dispose() { _ping?.cancel(); super.dispose(); }

  Future<void> _markCollected() async {
    setState(() => _busy = true);
    final pos = await LocationService.getCurrentLocation();
    await DriverApiService.deliveryAction(widget.ride.id, {'action': 'collected', 'lat': pos?.latitude, 'lng': pos?.longitude});
    // Accumulate distance every 20s while delivering
    _ping = Timer.periodic(const Duration(seconds: 20), (_) async {
      final p = await LocationService.getCurrentLocation();
      if (p != null) DriverApiService.deliveryAction(widget.ride.id, {'action': 'ping', 'lat': p.latitude, 'lng': p.longitude});
    });
    if (mounted) setState(() { _collected = true; _busy = false; });
  }

  Future<void> _markFailed() async {
    final reasons = ['Receiver unavailable', 'Wrong address', 'Receiver refused', 'Could not contact'];
    final reason = await showDialog<String>(context: context, builder: (_) => SimpleDialog(
      title: const Text('Return to Sender — reason'),
      children: reasons.map((x) => SimpleDialogOption(onPressed: () => Navigator.pop(context, x), child: Text(x))).toList()));
    if (reason == null) return;
    setState(() => _busy = true);
    _ping?.cancel();
    await DriverApiService.deliveryAction(widget.ride.id, {'action': 'failed', 'reason': reason});
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, InvoicePage.route, arguments: widget.ride);
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
    final res = await DriverApiService.deliveryAction(widget.ride.id, {'action': 'deliver', 'dropOtp': otp, 'proofPhoto': _proofPhoto, 'signature': _signatureUrl});
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
      appBar: AppBar(title: const Text('Parcel Delivery'), backgroundColor: AppColors.primary, foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.navigation), tooltip: 'Navigate', onPressed: _navigate)]),
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
          const SizedBox(height: 8),
          // Receiver signature (optional)
          OutlinedButton.icon(onPressed: _busy ? null : _captureSignature,
            icon: Icon(_signatureUrl != null ? Icons.check_circle : Icons.draw, color: _signatureUrl != null ? AppColors.green : AppColors.primary),
            label: Text(_signatureUrl != null ? 'Signature captured' : 'Capture receiver signature (optional)', style: TextStyle(color: _signatureUrl != null ? AppColors.green : AppColors.primary)),
            style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 46), side: BorderSide(color: _signatureUrl != null ? AppColors.green : AppColors.primary))),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.green, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 52)),
            onPressed: _busy ? null : _deliver,
            child: Text(_busy ? 'Verifying...' : '✅ Delivered — Enter Receiver OTP', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)))),
          const SizedBox(height: 8),
          Center(child: TextButton.icon(onPressed: _busy ? null : _markFailed,
            icon: const Icon(Icons.assignment_return, size: 16, color: AppColors.red),
            label: const Text('Receiver unavailable — Return to Sender', style: TextStyle(color: AppColors.red, fontSize: 13)))),
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
      SizedBox(width: 60, child: Text(l, style: TextStyle(fontSize: 12, color: AppColors.textGrey))),
      Expanded(child: Text(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark), maxLines: 2))]));
}

class _SigPainter extends CustomPainter {
  final List<Offset?> points;
  _SigPainter(this.points);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.black..strokeWidth = 2.5..strokeCap = StrokeCap.round;
    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) canvas.drawLine(points[i]!, points[i + 1]!, p);
    }
  }
  @override bool shouldRepaint(_SigPainter old) => true;
}
