import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../config/app_config.dart';
import '../../../models/models.dart';
import '../../../services/driver_api_service.dart';
import '../../../services/location_service.dart';
import '../logic/job_settlement.dart';
import 'collect_fare_page.dart';
import '../widgets/arrival_hint.dart';
import '../widgets/nav_map.dart';
import '../widgets/otp_dialog.dart';
import '../widgets/ride_shell.dart';
import '../widgets/ride_status_strip.dart';
import '../widgets/swipe_to_confirm.dart';

// Delivery flow after the pickup-OTP start: collect from the sender, deliver to
// the receiver (drop OTP). Laid out in the shared RideShell.
class DeliveryProgressPage extends StatefulWidget {
  static const route = '/delivery-progress';
  final RideRequestModel ride;

  /// Opened straight after the pickup OTP: that code is the sender's handover,
  /// so the parcel is marked collected at once and navigation heads for the
  /// receiver. It used to wait on a separate "Swipe once parcel is collected",
  /// with the map still pointing at the sender the driver was standing beside
  /// — and the sender's app still saying "Collecting parcel". The swipe stays
  /// as the way to retry if marking it collected fails.
  final bool collectOnOpen;

  const DeliveryProgressPage({super.key, required this.ride, this.collectOnOpen = false});
  @override
  State<DeliveryProgressPage> createState() => _DeliveryProgressPageState();
}

class _DeliveryProgressPageState extends State<DeliveryProgressPage> {
  late bool _collected;
  /// Delivered or returned before this screen opened; only settlement is left.
  late bool _pricedEarlier;
  bool _busy = false;
  String? _proofPhoto; // full url of captured proof
  String? _signatureUrl;
  final _picker = ImagePicker();
  Timer? _ping;
  final List<Offset?> _sigPoints = [];

  /// The last delivered/returned answer, kept so a cancelled collection or a
  /// failed settlement can be retried without pricing the job again.
  Map<String, dynamic>? _priced;
  bool _cashInHand = false;

  @override
  void initState() {
    super.initState();
    final p = widget.ride.progress;
    // A parcel already on its way used to reopen at "swipe once collected",
    // and swiping again re-anchored its distance to wherever the driver was.
    _collected = p.parcelCollected;
    _pricedEarlier = p.deliveryPhase == 'delivered' || p.deliveryPhase == 'returned';
    if (_collected && !_pricedEarlier) _startPinging();
    if (widget.collectOnOpen && !_collected && !_pricedEarlier) {
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _markCollected(); });
    }
  }

  @override
  void dispose() { _ping?.cancel(); super.dispose(); }

  // Accumulate distance every 20s while delivering.
  void _startPinging() {
    _ping ??= Timer.periodic(const Duration(seconds: 20), (_) async {
      final p = await LocationService.getCurrentLocation();
      if (p != null) {
        DriverApiService.deliveryAction(widget.ride.id, {'action': 'ping', 'lat': p.latitude, 'lng': p.longitude})
            .catchError((_) => <String, dynamic>{});
      }
    });
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
          if (dctx.mounted) Navigator.pop(dctx);
          if (bd == null) return;
          setState(() => _busy = true);
          final url = await DriverApiService.uploadBytes(bd.buffer.asUint8List(), 'signature.png');
          if (mounted) setState(() { _signatureUrl = url; _busy = false; });
        }, child: const Text('Save')),
      ])));
  }

  // "You have reached the sender / receiver", until the driver acts on it.
  final _arrivalHint = ArrivalHint();

  Future<void> _markCollected() async {
    setState(() => _busy = true);
    final pos = await LocationService.getCurrentLocation();
    Map<String, dynamic> res;
    try {
      res = await DriverApiService.deliveryAction(widget.ride.id, {'action': 'collected', 'lat': pos?.latitude, 'lng': pos?.longitude});
    } catch (_) {
      res = const {'error': 'No connection'};
    }
    if (!mounted) return;
    if (res['error'] != null) {
      // Used to move on regardless: the screen said "in transit" while the
      // server — and the sender's app — still said the parcel was uncollected.
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not mark collected: ${res['error']}'), backgroundColor: AppColors.red));
      return;
    }
    _arrivalHint.dismiss();
    _startPinging();
    setState(() { _collected = true; _busy = false; });
  }

  Future<void> _markFailed() async {
    _arrivalHint.dismiss();
    final reasons = ['Receiver unavailable', 'Wrong address', 'Receiver refused', 'Could not contact'];
    final reason = await showDialog<String>(context: context, builder: (dctx) => SimpleDialog(
      title: const Text('Return to Sender — reason'),
      children: reasons.map((x) => SimpleDialogOption(onPressed: () => Navigator.pop(dctx, x), child: Text(x))).toList()));
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    final res = await DriverApiService.deliveryAction(widget.ride.id, {'action': 'failed', 'reason': reason});
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['error'].toString()), backgroundColor: AppColors.red));
      return;
    }
    _ping?.cancel();
    // The driver still drove the job, so the delivery fare is still due — but no
    // COD, because the receiver never took the parcel.
    setState(() => _priced = res);
    await _collectAndSettle();
  }

  /// Takes the money at the door, then settles the ride — the server priced the
  /// job and said what is owed; the app never works the figure out itself.
  Future<void> _collectAndSettle() async {
    final res = _priced;
    if (res == null) return;
    final due = (res['amountDue'] as num?)?.toDouble() ?? 0;
    final cod = (res['codDue'] as num?)?.toDouble() ?? 0;
    // Once confirmed, a retry after a failed settlement goes straight to
    // settling — the driver is not asked to collect the same cash twice.
    if (due > 0 && !_cashInHand) {
      final collected = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => CollectFarePage(amount: due)));
      if (collected != true || !mounted) return;
      _cashInHand = true;
    }
    await _withBusy(() => collectAndSettle(context, ride: widget.ride, cashDue: 0,
      afterSettleNote: cod > 0
          ? 'COD ₹${cod.toStringAsFixed(0)} recorded — deducted from your wallet and paid to the sender'
          : null));
  }

  Future<void> _withBusy(Future<void> Function() body) async {
    setState(() => _busy = true);
    await body();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _captureProof() async {
    final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 60);
    if (x == null || !mounted) return;
    setState(() => _busy = true);
    final url = await DriverApiService.uploadFile(x);
    if (mounted) setState(() { _proofPhoto = url; _busy = false; });
  }

  Future<void> _deliver() async {
    if (_proofPhoto == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Capture proof-of-delivery photo first')));
      return;
    }
    _arrivalHint.dismiss();
    final otp = await OtpDialog.show(context,
        title: 'Enter Delivery OTP', label: 'OTP from Receiver', hint: 'e.g. 4821', action: 'Deliver');
    if (otp == null || otp.isEmpty || !mounted) return;
    setState(() => _busy = true);
    final res = await DriverApiService.deliveryAction(widget.ride.id, {'action': 'deliver', 'dropOtp': otp, 'proofPhoto': _proofPhoto, 'signature': _signatureUrl});
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['error'] != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['error'].toString()), backgroundColor: AppColors.red));
      return;
    }
    _ping?.cancel();
    setState(() => _priced = res);
    await _collectAndSettle();
  }

  Future<void> _finishEarlier() => _withBusy(() => finishPricedJob(context, widget.ride));

  @override
  Widget build(BuildContext context) {
    final r = widget.ride;
    final finishing = _pricedEarlier || _priced != null;
    // Only the account holder (the rider who booked) has an uploaded photo —
    // a typed-in sender name has no photo of its own. Used to only show it
    // when senderName was left blank, which it almost never is (the booking
    // form requires it), so the sender's photo was effectively always blank.
    final sender = RideContact(
      name: r.senderName.isNotEmpty ? r.senderName : r.userName,
      phone: r.senderPhone.isNotEmpty ? r.senderPhone : r.userPhone,
      role: 'Sender',
      picUrl: r.userProfilePicUrl,
    );
    final receiver = RideContact(
      name: r.receiverName.isNotEmpty ? r.receiverName : 'Receiver',
      phone: r.receiverPhone,
      role: 'Receiver',
    );

    return RideShell(
      rideId: r.id,
      vehicleType: r.rideType,
      // On the way to the receiver the map leads; at the sender, and when
      // finishing, the details do.
      driving: _collected && !finishing,
      // Sender until the parcel is collected, then receiver.
      leg: _collected
          ? NavLeg(label: 'Receiver', destLat: r.dropLat, destLng: r.dropLng, destAddress: r.dropAddress)
          : NavLeg(label: 'Pickup', destLat: r.pickupLat, destLng: r.pickupLng, destAddress: r.pickupAddress),
      fallbackPolyline: r.routePolyline,
      onArrived: () {
        if (!mounted) return;
        // Straight after the OTP the driver is standing at the sender with the
        // parcel in hand: "collect the parcel" would only be noise.
        if (!_collected && widget.collectOnOpen) return;
        _arrivalHint.show(context, _collected
            ? 'You have reached the receiver — capture proof and enter the OTP'
            : 'You have reached the sender — collect the parcel');
      },
      phase: finishing ? 'PARCEL · FINISHING' : (_collected ? 'PARCEL · TO RECEIVER' : 'PARCEL · TO SENDER'),
      // The COD reminder — the thing the driver must not forget at the door —
      // lives in the always-visible strip, not in anything that scrolls.
      status: RideStatusStrip(
        phase: finishing ? 'Finishing' : (_collected ? 'To receiver' : 'To sender'),
        accruing: finishing ? null : r.codAmount,
        accruingLabel: 'COD to collect',
        metrics: [
          RideStatusMetric(Icons.inventory_2_outlined, r.itemType.isNotEmpty ? r.itemType : 'Parcel'),
          if (r.isFragile) const RideStatusMetric(Icons.warning_amber, 'Fragile', warn: true),
        ],
      ),
      // The person at the door is the one the driver needs to reach.
      contact: _collected ? receiver : sender,
      chatWith: r.userName,
      details: [
        if (r.codAmount > 0 && !finishing) Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12),
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
        if (r.parcelPhotos.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: SizedBox(height: 72,
          child: ListView(scrollDirection: Axis.horizontal, children: r.parcelPhotos.map((u) => Container(width: 72, height: 72, margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), image: DecorationImage(image: NetworkImage(AppConfig.imageUrl(u)), fit: BoxFit.cover)))).toList()))),
        const SizedBox(height: 10),
        // Phone numbers deliberately not printed here — the header's call
        // button (RideShell's `contact`) already reaches this same person by
        // number, without leaving the digits sitting in plain text where a
        // screenshot or a glance at the driver's phone could pick them up.
        _card('Sender', [
          _line(Icons.person_outline, 'Name', sender.name),
          _line(Icons.radio_button_checked, 'Pickup', r.pickupAddress),
        ]),
        const SizedBox(height: 10),
        _card('Receiver', [
          _line(Icons.person, 'Name', r.receiverName.isNotEmpty ? r.receiverName : '—'),
          _line(Icons.location_on, 'Drop', r.dropAddress),
        ]),
        if (_proofPhoto != null) Padding(padding: const EdgeInsets.only(top: 10), child: ClipRRect(borderRadius: BorderRadius.circular(8),
          child: Image.network(_proofPhoto!, height: 120, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()))),
      ],
      actions: finishing
          ? [
              SwipeToConfirm(
                label: 'Swipe to finish the delivery',
                tone: SwipeTone.success,
                icon: Icons.check_circle_outline,
                enabled: !_busy,
                onConfirm: _pricedEarlier && _priced == null ? _finishEarlier : _collectAndSettle,
              ),
            ]
          : !_collected
              ? [
                  // Swipe: unlike the final hand-over, collection has no OTP behind
                  // it, so one accidental tap would mark a parcel in transit that is not.
                  SwipeToConfirm(
                    label: 'Swipe once parcel is collected',
                    tone: SwipeTone.success,
                    icon: Icons.inventory_2_rounded,
                    enabled: !_busy,
                    onConfirm: _markCollected,
                  ),
                ]
              : [
                  Row(children: [
                    Expanded(child: _evidenceButton(
                      done: _proofPhoto != null,
                      icon: Icons.camera_alt,
                      label: _proofPhoto != null ? 'Photo taken' : 'Proof photo',
                      onTap: _captureProof,
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: _evidenceButton(
                      done: _signatureUrl != null,
                      icon: Icons.draw,
                      label: _signatureUrl != null ? 'Signed' : 'Signature',
                      onTap: _captureSignature,
                    )),
                  ]),
                  const SizedBox(height: 8),
                  SizedBox(width: double.infinity, child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.green, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50)),
                    onPressed: _busy ? null : _deliver,
                    child: Text(_busy ? 'Verifying…' : 'Delivered — enter receiver OTP',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)))),
                  TextButton.icon(onPressed: _busy ? null : _markFailed,
                    icon: const Icon(Icons.assignment_return, size: 16, color: AppColors.red),
                    label: const Text('Receiver unavailable — return to sender', style: TextStyle(color: AppColors.red, fontSize: 13))),
                ],
    );
  }

  Widget _evidenceButton({required bool done, required IconData icon, required String label, required VoidCallback onTap}) =>
      OutlinedButton.icon(
        onPressed: _busy ? null : onTap,
        icon: Icon(done ? Icons.check_circle : icon, size: 18, color: done ? AppColors.green : AppColors.primary),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: done ? AppColors.green : AppColors.primary)),
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          side: BorderSide(color: done ? AppColors.green : AppColors.primary)),
      );

  Widget _card(String title, List<Widget> rows) => Container(
    width: double.infinity, padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(14)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.teal)),
      const SizedBox(height: 8), ...rows,
    ]));

  Widget _line(IconData i, String l, String v) => Padding(padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [Icon(i, size: 16, color: AppColors.textGrey), const SizedBox(width: 8),
      SizedBox(width: 60, child: Text(l, style: TextStyle(fontSize: 12, color: AppColors.textGrey))),
      Expanded(child: Text(v, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDark), maxLines: 2, overflow: TextOverflow.ellipsis))]));
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
