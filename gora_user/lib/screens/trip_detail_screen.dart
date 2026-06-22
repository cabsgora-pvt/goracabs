import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../config/app_config.dart';
import '../theme/app_theme.dart';
import '../utils/polyline_utils.dart';

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
    final pickup = LatLng(_d(ride['pickupLat']), _d(ride['pickupLng']));
    final drop = LatLng(_d(ride['dropLat']), _d(ride['dropLng']));
    final encoded = (ride['routePolyline'] as String?) ?? '';
    final pts = encoded.isNotEmpty ? decodePolyline(encoded) : [pickup, drop];
    final driverPic = (ride['driverPic'] as String?) ?? '';
    final carImg = (ride['vehicleImageUrl'] as String?) ?? '';
    final carImgUrl = carImg.isEmpty ? '' : AppConfig.imageUrl(carImg);

    return Scaffold(
      appBar: AppBar(
        title: Text('Trip Details', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold)),
        elevation: 0,
        leading: IconButton(icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface), onPressed: () => Navigator.pop(context)),
      ),
      body: ListView(children: [
        // Map
        SizedBox(
          height: 200,
          child: GoogleMap(
            initialCameraPosition: CameraPosition(target: pickup, zoom: 12),
            onMapCreated: (c) {
              final b = boundsFromPoints(pts);
              if (b != null) Future.delayed(const Duration(milliseconds: 300), () => c.animateCamera(CameraUpdate.newLatLngBounds(b, 50)));
            },
            markers: {
              Marker(markerId: const MarkerId('p'), position: pickup, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)),
              Marker(markerId: const MarkerId('d'), position: drop, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed)),
            },
            polylines: {Polyline(polylineId: const PolylineId('r'), points: pts, color: AppTheme.primaryBlue, width: 5)},
            zoomControlsEnabled: false, myLocationButtonEnabled: false,
          ),
        ),

        // Service badge + status + date
        _card(context, Row(children: [
          _badge(_serviceLabel(), _serviceColor()),
          const Spacer(),
          Text(ride['date']?.toString() ?? '', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ])),

        // Route
        _card(context, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _locRow(Icons.radio_button_checked, Colors.green, 'PICKUP', from),
          const Padding(padding: EdgeInsets.only(left: 9), child: SizedBox(height: 18, child: VerticalDivider(width: 2, thickness: 2))),
          _locRow(Icons.location_on, Colors.red, 'DROP', to),
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
          ..._fareRows(context),
        ])),

        const SizedBox(height: 20),
      ]),
    );
  }

  // Service-specific fare rows
  List<Widget> _fareRows(BuildContext context) {
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
      if (_n(ride['tollCharge']) > 0) rows.add(_fareRow(context, 'Toll', '₹${_n(ride['tollCharge'])}'));
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

    if (_n(ride['tip']) > 0) rows.add(_fareRow(context, 'Tip', '₹${_n(ride['tip'])}', color: Colors.green));
    rows.add(const Divider(height: 20));
    final total = _n(ride['finalFare']) > 0 ? _n(ride['finalFare']) : _n(ride['total']);
    rows.add(_fareRow(context, 'Total Paid', '₹$total', bold: true, color: AppTheme.primaryBlue));
    rows.add(const SizedBox(height: 4));
    rows.add(Text('Payment: ${(ride['paymentMode'] ?? 'Cash').toString().toUpperCase()}', style: TextStyle(fontSize: 11, color: Colors.grey[500])));
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
  Widget _locRow(IconData i, Color c, String label, String addr) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(i, color: c, size: 18), const SizedBox(width: 10),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[500], fontWeight: FontWeight.w600)),
      Text(addr, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
    ])),
  ]);
  Widget _fareRow(BuildContext context, String l, String v, {bool bold = false, Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(l, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: color ?? Theme.of(context).colorScheme.onSurface)),
      Text(v, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color ?? Theme.of(context).colorScheme.onSurface)),
    ]),
  );
}
