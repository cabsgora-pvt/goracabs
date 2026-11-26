import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../config/app_config.dart';
import '../theme/app_theme.dart';
import '../utils/receipt.dart';
import '../utils/trip_map.dart';
import '../widgets/ride_service_panels.dart';
import '../utils/map_markers.dart';
import 'invoice_screen.dart';
import 'rating_screen.dart';
import 'support_screen.dart';

// Unified trip detail page — works for taxi, bike, cab, rental, outstation.
// Shows route map, driver card, car image, full fare breakdown + service-specific extras.
class TripDetailScreen extends StatelessWidget {
  final Map<String, dynamic> ride;
  const TripDetailScreen({super.key, required this.ride});

  String get _service => (ride['service'] ?? 'taxi').toString();
  int _n(dynamic v) => (v as num?)?.toInt() ?? 0;
  double _d(dynamic v) => (v as num?)?.toDouble() ?? 0;

  @override
  Widget build(BuildContext context) {
    final from = ride['from']?.toString() ?? '';
    final to = ride['to']?.toString() ?? '';
    // A missing point is left off the map (no 0,0 pin); no point at all, no map.
    final m = TripMapPoints.of(ride);
    final pickup = m.pickup, drop = m.drop, pts = m.route, center = m.center;
    final receipt = TripReceipt.from(ride);
    final driverPic = (ride['driverPic'] as String?) ?? '';
    final carImg = (ride['vehicleImageUrl'] as String?) ?? '';
    final carImgUrl = carImg.isEmpty ? '' : AppConfig.imageUrl(carImg);

    return Scaffold(
      appBar: AppBar(
        title: Text('Trip Details', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold)),
        elevation: 0,
        leading: IconButton(icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface), onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(
            icon: Icon(Icons.share_outlined, color: Theme.of(context).colorScheme.onSurface),
            onPressed: () => Share.share(_receiptText(), subject: 'Your Gora Cabs receipt'),
          ),
        ],
      ),
      body: ListView(children: [
        // Map
        if (center != null)
          SizedBox(
            height: 200,
            child: PlaceGlyphs(builder: (context, glyphs) => GoogleMap(
              initialCameraPosition: CameraPosition(target: center, zoom: 12),
              onMapCreated: (c) {
                final b = m.bounds;
                if (b != null) Future.delayed(const Duration(milliseconds: 300), () => c.animateCamera(CameraUpdate.newLatLngBounds(b, 50)));
              },
              markers: {
                if (pickup != null)
                  Marker(markerId: const MarkerId('p'), position: pickup, anchor: glyphs.pickupAnchor, icon: glyphs.pickup),
                if (drop != null)
                  Marker(markerId: const MarkerId('d'), position: drop, anchor: glyphs.dropAnchor, icon: glyphs.drop),
              },
              polylines: {
                if (pts.length >= 2)
                  Polyline(polylineId: const PolylineId('r'), points: pts, color: AppTheme.primaryBlue, width: 5),
              },
              zoomControlsEnabled: false, myLocationButtonEnabled: false,
            )),
          ),

        // Service badge + status + date
        // The date takes what the badge leaves and wraps, rather than overflow
        // with a long label ("OUTSTATION · One Way") at a large text size.
        _card(context, Row(children: [
          _badge(_serviceLabel(), _serviceColor()),
          const SizedBox(width: 12),
          Expanded(child: Text(ride['date']?.toString() ?? '', textAlign: TextAlign.right,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
        ])),

        // Route
        _card(context, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _locRow(context, Icons.radio_button_checked, Colors.green, 'PICKUP', from),
          for (final (i, s) in receipt.stops.indexed) ...[
            const Padding(padding: EdgeInsets.only(left: 9), child: SizedBox(height: 14, child: VerticalDivider(width: 2, thickness: 2))),
            _locRow(context, Icons.more_vert, Colors.orange, 'STOP ${i + 1}', s),
          ],
          if (to.isNotEmpty) ...[
            const Padding(padding: EdgeInsets.only(left: 9), child: SizedBox(height: 18, child: VerticalDivider(width: 2, thickness: 2))),
            _locRow(context, Icons.location_on, Colors.red, 'DROP', to),
          ],
        ])),

        // Cancelled: who and why
        if (receipt.isCancelled)
          _card(context, Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.cancel_outlined, color: Color(0xFFB91C1C), size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(receipt.cancellationLine,
                key: const ValueKey('trip-cancel-line'),
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
          ])),

        // Driver + car
        if (ride['driver'] != null && ride['driver'] != '—')
          _card(context, Row(children: [
            CircleAvatar(radius: 26, backgroundColor: AppTheme.primaryBlue.withOpacity(0.1),
              backgroundImage: driverPic.isNotEmpty ? NetworkImage(driverPic) : null,
              child: driverPic.isEmpty ? Text((ride['driver'] as String).isNotEmpty ? (ride['driver'] as String)[0].toUpperCase() : 'D',
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryBlue, fontSize: 18)) : null),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ride['driver']?.toString() ?? 'Driver', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text([ride['driverVehicleModel'], ride['driverVehicleNumber']].where((s) => (s as String?)?.isNotEmpty == true).join(' • '),
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              if (_d(ride['driverRatingVal']) > 0) Row(children: [
                const Icon(Icons.star, size: 14, color: Colors.amber), const SizedBox(width: 2),
                Text(_d(ride['driverRatingVal']).toStringAsFixed(1), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
            ])),
            if (carImgUrl.isNotEmpty) SizedBox(width: 80, height: 54, child: Image.network(carImgUrl, fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(Icons.directions_car, size: 40, color: Colors.grey))),
          ])),

        // Fare breakdown
        _card(context, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Fare Breakdown', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ..._fareRows(context, receipt),
        ])),

        // Same actions as the trip's row in "Your trips"
        _card(context, Wrap(spacing: 8, runSpacing: 8, children: [
          _action(context, const ValueKey('trip-help'), Icons.support_agent, 'Help with this trip', () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportScreen()))),
          if (!receipt.isCancelled)
            _action(context, const ValueKey('trip-invoice'), Icons.receipt_long_outlined, 'Invoice', () =>
                Navigator.push(context, MaterialPageRoute(builder: (_) => InvoiceScreen(ride: ride)))),
          if (_canRate)
            _action(context, const ValueKey('trip-rate'), Icons.star_border_rounded, 'Rate', () =>
                Navigator.push(context, MaterialPageRoute(builder: (_) => RatingScreen(
                  driverName: (ride['driver'] ?? 'Driver').toString(),
                  vehicleName: (ride['vehicle'] ?? '').toString(),
                  selectedTip: 0,
                  rideId: (ride['id'] ?? '').toString().isEmpty ? null : ride['id'].toString(),
                )))),
        ])),

        const SizedBox(height: 20),
      ]),
    );
  }

  // Service-specific fare rows
  /// Completed and not rated yet (the history row's rule).
  bool get _canRate {
    final st = (ride['status'] ?? '').toString().toLowerCase();
    final rated = (ride['rating'] as num?)?.toDouble() ?? 0;
    return st == 'completed' && rated <= 0 && (ride['id'] ?? '').toString().isNotEmpty;
  }

  Widget _action(BuildContext context, Key key, IconData icon, String label, VoidCallback onTap) => Material(
    key: key,
    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 17, color: Theme.of(context).colorScheme.onSurface),
            const SizedBox(width: 6),
            Flexible(child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface))),
          ]),
        ),
      ),
    ),
  );

  List<Widget> _fareRows(BuildContext context, TripReceipt receipt) {
    final rows = <Widget>[];
    final base = _n(ride['baseFare'] ?? ride['fare']);
    rows.add(_fareRow(context, 'Base fare', '₹$base'));

    if (_service == 'rental') {
      rows.add(_fareRow(context, 'Package', '${_n(ride['packageHours'])} hr / ${_n(ride['packageKm'])} km'));
      if (_d(ride['actualHours']) > 0 || _d(ride['actualKm']) > 0)
        rows.add(_fareRow(context, 'Used', '${_d(ride['actualHours']).toStringAsFixed(1)} hr / ${_d(ride['actualKm']).toStringAsFixed(1)} km'));
      if (_n(ride['extraHoursCharge']) > 0) rows.add(_fareRow(context, 'Extra hours', '₹${_n(ride['extraHoursCharge'])}', color: Colors.orange));
      if (_n(ride['extraKmCharge']) > 0) rows.add(_fareRow(context, 'Extra km', '₹${_n(ride['extraKmCharge'])}', color: Colors.orange));
      if (_n(ride['nightChargeRental']) > 0) rows.add(_fareRow(context, 'Night charge', '₹${_n(ride['nightChargeRental'])}'));
    } else if (_service == 'outstation') {
      rows.add(_fareRow(context, 'Trip type', ride['tripType'] == 'round_trip' ? 'Round Trip' : 'One Way'));
      if (_n(ride['numPassengers']) > 0) rows.add(_fareRow(context, 'Passengers', '${_n(ride['numPassengers'])}'));
      rows.add(_fareRow(context, 'Distance', '${_d(ride['distance']).toStringAsFixed(0)} km'));
      if (_n(ride['nightHaltCharge']) > 0) rows.add(_fareRow(context, 'Night halt', '₹${_n(ride['nightHaltCharge'])}', color: Colors.orange));
      if (_n(ride['emptyReturnCharge']) > 0) rows.add(_fareRow(context, 'Empty return', '₹${_n(ride['emptyReturnCharge'])}', color: Colors.orange));
      // Always shown for outstation, even at ₹0. Paid to the driver directly,
      // so it sits outside the fare and is added to the total below.
      rows.add(_fareRow(context, 'Tolls (paid to driver)', '₹${_n(ride['tollCharge'])}'));
      if (tollsOf(ride).isNotEmpty) {
        final id = (ride['id'] ?? '').toString();
        rows.add(Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 4),
          child: TollList(ride: ride, rideId: id.isEmpty ? null : id),
        ));
      }
    } else if (_service == 'hire_driver') {
      rows.add(_fareRow(context, 'Transmission', ride['transmission'] == 'automatic' ? 'Automatic' : 'Manual'));
      rows.add(_fareRow(context, 'Duration', '${_n(ride['hireTotalHours'])} hr'));
      rows.add(_fareRow(context, 'Rate', '₹${_n(ride['hirePerHour'])}/hr'));
      final s = _fmtDt(ride['hireStartAt']?.toString() ?? ''), e = _fmtDt(ride['hireEndAt']?.toString() ?? '');
      if (s.isNotEmpty || e.isNotEmpty) rows.add(_fareRow(context, 'Schedule', '$s → $e'));
    } else if (_service == 'delivery') {
      rows.add(_fareRow(context, 'Item', (ride['itemType'] ?? 'Parcel').toString()));
      if (_d(ride['weightKg']) > 0) rows.add(_fareRow(context, 'Weight', '${_d(ride['weightKg']).toStringAsFixed(0)} kg'));
      if ((ride['packageSize'] ?? '').toString().isNotEmpty) rows.add(_fareRow(context, 'Size', ride['packageSize'].toString()));
      rows.add(_fareRow(context, 'Sender', (ride['senderName'] ?? '').toString()));
      rows.add(_fareRow(context, 'Receiver', (ride['receiverName'] ?? '').toString()));
      if ((ride['isFragile'] as bool?) ?? false) rows.add(_fareRow(context, 'Handling', 'Fragile', color: Colors.orange));
      if (_n(ride['codAmount']) > 0) rows.add(_fareRow(context, 'COD collected', '₹${_n(ride['codAmount'])}', color: Colors.orange));
      rows.add(_fareRow(context, 'Distance', '${_d(ride['distance']).toStringAsFixed(1)} km'));
    } else {
      rows.add(_fareRow(context, 'Distance', '${_d(ride['distance']).toStringAsFixed(1)} km'));
    }

    if (receipt.waiting > 0) rows.add(_fareRow(context, 'Waiting charge', '₹${receipt.waiting}'));
    if (_n(ride['tip']) > 0) rows.add(_fareRow(context, 'Tip', '₹${_n(ride['tip'])}', color: Colors.green));
    if (receipt.couponDiscount > 0) {
      final code = receipt.couponCode.isEmpty ? '' : ' (${receipt.couponCode})';
      // A rental's fare already has the coupon off: shown, not subtracted again.
      rows.add(receipt.couponOff > 0
          ? _fareRow(context, 'Coupon$code', '-₹${receipt.couponOff}', color: Colors.green)
          : _fareRow(context, 'Coupon$code (included)', '₹${receipt.couponDiscount}', color: Colors.green));
    }
    if (receipt.isCancelled && receipt.cancellationFee > 0) {
      rows.add(_fareRow(context, 'Cancellation fee', '₹${receipt.cancellationFee}', color: Colors.orange));
    }
    rows.add(const Divider(height: 20));
    rows.add(_fareRow(context, receipt.totalLabel(), '₹${receipt.totalValue}', bold: true,
        color: receipt.isCancelled ? const Color(0xFFB91C1C) : AppTheme.primaryBlue));
    rows.add(const SizedBox(height: 4));
    rows.add(Text('Payment: ${TripReceipt.paymentLine((ride['paymentMode'] ?? 'Cash').toString(), receipt.paymentStatus)}',
        style: TextStyle(fontSize: 12, color: Colors.grey[600])));
    return rows;
  }

  String _serviceLabel() {
    switch (_service) {
      case 'rental': return 'RENTAL · ${_n(ride['packageHours'])}hr';
      case 'outstation': return 'OUTSTATION · ${ride['tripType'] == 'round_trip' ? 'Round' : 'One Way'}';
      case 'hire_driver': return 'HIRE DRIVER · ${_n(ride['hireTotalHours'])}hr';
      case 'delivery': return 'PARCEL · ${(ride['itemType'] ?? '').toString()}';
      default: return (ride['vehicle'] ?? 'TAXI').toString().toUpperCase();
    }
  }
  Color _serviceColor() => _service == 'outstation' ? Colors.orange
      : _service == 'rental' ? Colors.purple
      : _service == 'hire_driver' ? Colors.indigo
      : _service == 'delivery' ? Colors.teal : AppTheme.primaryBlue;

  String _fmtDt(String iso) {
    if (iso.isEmpty) return '';
    try { final d = DateTime.parse(iso).toLocal(); return '${d.day}/${d.month} ${d.hour}:${d.minute.toString().padLeft(2, '0')}'; }
    catch (_) { return ''; }
  }

  // A plain-text version of this same receipt — same total the screen shows,
  // computed the same way — for sharing outside the app (WhatsApp, email, etc).
  String _receiptText() {
    final from = ride['from']?.toString() ?? '';
    final to = ride['to']?.toString() ?? '';
    final driver = ride['driver']?.toString();
    final receipt = TripReceipt.from(ride);
    final id = (ride['id'] ?? '').toString();
    final lines = <String>[
      'Gora Cabs — ${_serviceLabel()}',
      if ((ride['date'] ?? '').toString().isNotEmpty) (ride['date']).toString(),
      '',
      'From: $from',
      for (final (i, s) in receipt.stops.indexed) 'Stop ${i + 1}: $s',
      if (to.isNotEmpty) 'To: $to',
      if (driver != null && driver.isNotEmpty && driver != '—') 'Driver: $driver',
      if (receipt.isCancelled) receipt.cancellationLine,
      '',
      if (receipt.waiting > 0) 'Waiting charge: ₹${receipt.waiting}',
      if (receipt.couponOff > 0) 'Coupon: -₹${receipt.couponOff}',
      '${receipt.totalLabel()}: ₹${receipt.totalValue}',
      'Payment: ${TripReceipt.paymentLine((ride['paymentMode'] ?? 'Cash').toString(), receipt.paymentStatus)}',
      if (id.isNotEmpty) 'Ride ID: $id',
    ];
    return lines.join('\n');
  }

  Widget _card(BuildContext context, Widget child) => Container(
    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0), padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey[100]!)),
    child: child,
  );
  Widget _badge(String t, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
    child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c, letterSpacing: 0.3)),
  );
  Widget _locRow(BuildContext context, IconData i, Color c, String label, String addr) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(i, color: c, size: 18), const SizedBox(width: 10),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w600)),
      Text(addr, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
    ])),
  ]);
  // The label takes the room left by the amount and wraps if it must: a long
  // label ("Tolls (paid to driver)") beside an amount overflowed a narrow
  // screen, and the amount is the part that must always show in full.
  Widget _fareRow(BuildContext context, String l, String v, {bool bold = false, Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Text(l, maxLines: 2, overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: color ?? Theme.of(context).colorScheme.onSurface))),
      const SizedBox(width: 12),
      Text(v, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color ?? Theme.of(context).colorScheme.onSurface)),
    ]),
  );
}
