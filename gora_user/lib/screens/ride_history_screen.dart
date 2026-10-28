import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../config/app_config.dart';
import '../theme/app_theme.dart';
import 'trip_detail_screen.dart';
import '../services/api_service.dart';
import '../utils/map_markers.dart';
import '../utils/polyline_utils.dart';
import '../widgets/ride_ui/ride_ui.dart';
import 'invoice_screen.dart';
import 'hire_driver_booking_details_screen.dart';
import 'rating_screen.dart';

/// "Your trips": every booking the rider has made, newest first, across all
/// services (rides, parcels, rentals, intercity, hire a driver), in one list.
///
/// The old screen split them into collapsed per-service accordions and had no
/// section for parcels at all, so parcels, and anything in a closed section,
/// never showed.
class RideHistoryScreen extends StatefulWidget {
  const RideHistoryScreen({super.key});

  @override
  State<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

/// Filter chips: label to service values (null = everything).
const _filters = <String, List<String>?>{
  'All': null,
  'Rides': ['taxi'],
  'Parcels': ['delivery'],
  'Rentals': ['rental'],
  'Intercity': ['outstation'],
  'Hire driver': ['hire_driver'],
};

class _RideHistoryScreenState extends State<RideHistoryScreen> {
  List<Map<String, dynamic>> _myRides = [];
  bool _loadingRides = true;
  String _filter = 'All';

  @override
  void initState() {
    super.initState();
    _loadMyRides();
  }

  Future<void> _loadMyRides() async {
    try {
      final res = await ApiService.getMyRides();
      final list = (res['rides'] as List?) ?? [];
      if (!mounted) return;
      setState(() {
        // Parsed ride by ride: one record with an unexpected field must not
        // take every other trip off the screen with it.
        _myRides = list.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).map<Map<String, dynamic>?>((r) {
          try {
          final svc = _strOf(r['service']) ?? 'taxi';
          final num fare = (r['fare'] is num) ? r['fare'] as num : (num.tryParse('${r['fare'] ?? ''}') ?? 0);
          final num tip = (r['tip'] is num) ? r['tip'] as num : 0;
          final num total = (r['totalFare'] is num) ? r['totalFare'] as num : (fare + tip);
          final status = (r['status'] ?? '').toString();
          final dr = r['driver'] is Map ? Map<String, dynamic>.from(r['driver'] as Map) : null;
          final driverPic = (dr?['profilePicUrl'] ?? '').toString();
          return {
            'id': r['_id']?.toString() ?? '',
            'date': r['createdAt'] != null
                ? _formatDate(r['createdAt'].toString())
                : '',
            'from': (r['pickupAddress'] ?? '').toString(),
            'to': (r['dropAddress'] ?? '').toString(),
            'riderName': (r['riderName'] ?? '').toString(),
            'driver': (dr?['name'] ?? r['driverName'] ?? '—').toString(),
            'driverPic': driverPic.isEmpty ? '' : AppConfig.imageUrl(driverPic),
            'driverVehicleModel': (dr?['vehicleModel'] ?? '').toString(),
            'driverVehicleNumber': (dr?['vehicleNumber'] ?? '').toString(),
            'driverRatingVal': _numOf(dr?['rating'])?.toDouble() ?? 0,
            'fare': '₹$total',
            'baseFare': fare,
            'tip': tip,
            'total': total,
            'status': status == 'completed'
                ? 'Completed'
                : status == 'cancelled'
                    ? 'Cancelled'
                    : status,
            'rating': _numOf(r['driverRating'])?.toDouble() ?? 0,
            'createdAt': (r['createdAt'] ?? '').toString(),
            'vehicle': (r['vehicleType'] ?? '').toString(),
            'pickupLat': _numOf(r['pickupLat'])?.toDouble() ?? 0,
            'pickupLng': _numOf(r['pickupLng'])?.toDouble() ?? 0,
            'dropLat': _numOf(r['dropLat'])?.toDouble() ?? 0,
            'dropLng': _numOf(r['dropLng'])?.toDouble() ?? 0,
            'routePolyline': _strOf(r['routePolyline']) ?? '',
            'service': svc,
            'tripType': _strOf(r['tripType']) ?? 'one_way',
            'numPassengers': _numOf(r['numPassengers'])?.toInt() ?? 0,
            'duration': _numOf(r['duration'])?.toInt() ?? 0,
            'distance': _numOf(r['distance'])?.toDouble() ?? 0,
            'paymentMode': (r['paymentMode'] ?? 'cash').toString(),
            'vehicleImageUrl': _strOf(r['vehicleImageUrl']) ?? '',
            // Rental extras
            'packageHours': _numOf(r['packageHours'])?.toInt() ?? 0,
            'packageKm': _numOf(r['packageKm'])?.toInt() ?? 0,
            'actualHours': _numOf(r['actualHours'])?.toDouble() ?? 0,
            'actualKm': _numOf(r['actualKm'])?.toDouble() ?? 0,
            'extraHoursCharge': _numOf(r['extraHoursCharge'])?.toInt() ?? 0,
            'extraKmCharge': _numOf(r['extraKmCharge'])?.toInt() ?? 0,
            'nightChargeRental': _numOf(r['nightChargeRental'])?.toInt() ?? 0,
            'finalFare': _numOf(r['finalFare'])?.toInt() ?? 0,
            // Outstation extras
            'nightHaltCharge': _numOf(r['nightHaltCharge'])?.toInt() ?? 0,
            'emptyReturnCharge': _numOf(r['emptyReturnCharge'])?.toInt() ?? 0,
            'tollCharge': _numOf(r['tollCharge'])?.toInt() ?? 0,
            'tolls': (r['tolls'] is List ? r['tolls'] as List : null) ?? const [],
            // Hire extras
            'hireTotalHours': _numOf(r['hireTotalHours'])?.toInt() ?? 0,
            'hirePerHour': _numOf(r['hirePerHour'])?.toInt() ?? 0,
            'transmission': (r['transmission'] ?? '').toString(),
            'hireStartAt': (r['hireStartAt'] ?? '').toString(),
            'hireEndAt': (r['hireEndAt'] ?? '').toString(),
            // Delivery extras
            'senderName': (r['senderName'] ?? '').toString(),
            'receiverName': (r['receiverName'] ?? '').toString(),
            'itemType': (r['itemType'] ?? '').toString(),
            'weightKg': _numOf(r['weightKg'])?.toDouble() ?? 0,
            'packageSize': (r['packageSize'] ?? '').toString(),
            'isFragile': r['isFragile'] == true,
            'codAmount': _numOf(r['codAmount'])?.toInt() ?? 0,
            'parcelPhotos': (r['parcelPhotos'] is List ? r['parcelPhotos'] as List : null) ?? [],
            'deliveryProofPhoto': (r['deliveryProofPhoto'] ?? '').toString(),
          };
          } catch (e) {
            debugPrint('ride history: skipped a ride that did not parse: $e');
            return null;
          }
        }).whereType<Map<String, dynamic>>().toList();
        _loadingRides = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingRides = false);
    }
  }

  static num? _numOf(dynamic v) => v is num ? v : num.tryParse('${v ?? ''}');
  static String? _strOf(dynamic v) => v == null ? null : v.toString();

  String _formatDate(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      return '${d.day}/${d.month}/${d.year}, ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  // Open a bottom sheet with a static map showing the saved trip polyline
  void _showRouteReplay(Map<String, dynamic> ride) {
    final encoded = (ride['routePolyline'] as String?) ?? '';
    final pickup = LatLng((ride['pickupLat'] as double?) ?? 0, (ride['pickupLng'] as double?) ?? 0);
    final drop = LatLng((ride['dropLat'] as double?) ?? 0, (ride['dropLng'] as double?) ?? 0);
    final pts = encoded.isNotEmpty ? decodePolyline(encoded) : <LatLng>[pickup, drop];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;
        return SizedBox(
          height: size.height * 0.7,
          child: Column(
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(children: [
                  const Icon(Icons.route, color: AppTheme.primaryBlue),
                  const SizedBox(width: 8),
                  const Text('Trip Route', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                ]),
              ),
              Expanded(
                child: PlaceGlyphs(builder: (context, glyphs) => GoogleMap(
                  initialCameraPosition: CameraPosition(target: pickup, zoom: 13),
                  onMapCreated: (c) {
                    final b = boundsFromPoints(pts);
                    if (b != null) {
                      // Slight delay so the map is laid out before camera animates
                      Future.delayed(const Duration(milliseconds: 300), () {
                        c.animateCamera(CameraUpdate.newLatLngBounds(b, 60));
                      });
                    }
                  },
                  myLocationEnabled: false,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: true,
                  markers: {
                    Marker(markerId: const MarkerId('pickup'), position: pickup, anchor: glyphs.pickupAnchor, icon: glyphs.pickup, infoWindow: InfoWindow(title: 'Pickup', snippet: ride['from']?.toString())),
                    Marker(markerId: const MarkerId('drop'),   position: drop, anchor: glyphs.dropAnchor, icon: glyphs.drop,   infoWindow: InfoWindow(title: 'Drop',   snippet: ride['to']?.toString())),
                  },
                  polylines: {
                    Polyline(polylineId: const PolylineId('route'), points: pts, color: AppTheme.primaryBlue, width: 5),
                  },
                )),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Theme.of(context).cardColor, border: Border(top: BorderSide(color: Colors.grey[200]!))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [const Icon(Icons.radio_button_checked, size: 14, color: Colors.green), const SizedBox(width: 8), Expanded(child: Text(ride['from']?.toString() ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)))]),
                  const SizedBox(height: 6),
                  Row(children: [const Icon(Icons.location_on, size: 14, color: Colors.red), const SizedBox(width: 8), Expanded(child: Text(ride['to']?.toString() ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)))]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Text(ride['date']?.toString() ?? '', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    const Spacer(),
                    Text(ride['fare']?.toString() ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
                  ]),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = _filters[_filter];
    final rides = services == null ? _myRides : _myRides.where((r) => services.contains(r['service'])).toList();
    // Only the chips for services the rider has actually used.
    final used = _myRides.map((r) => r['service']).toSet();
    final chips = _filters.entries.where((e) => e.value == null || e.value!.any(used.contains)).map((e) => e.key).toList();
    // As a home tab there is nothing to go back to; as a pushed page there is.
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: RideUi.surface(context),
      body: Column(children: [
        if (canPop) const ServiceBackBar() else const SafeArea(bottom: false, child: SizedBox(height: 12)),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadMyRides,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                const ServiceTitle(title: 'Your trips'),
                if (!_loadingRides && chips.length > 2) ...[
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: chips.map((c) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ServiceChip(label: c, selected: _filter == c, onTap: () => setState(() => _filter = c)),
                      )).toList(),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (_loadingRides)
                  const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
                else if (rides.isEmpty)
                  _empty()
                else
                  for (var i = 0; i < rides.length; i++) ...[
                    if (i > 0) const RideDivider(indent: 70),
                    _buildRideCard(rides[i]),
                  ],
              ],
            ),
          ),
        ),
      ]),
    );
  }

  Widget _empty() => Padding(
    padding: const EdgeInsets.only(top: 48),
    child: Column(children: [
      Container(
        width: 72, height: 72,
        decoration: BoxDecoration(color: RideUi.tile(context), shape: BoxShape.circle),
        child: Icon(Icons.receipt_long_outlined, size: 32, color: RideUi.muted(context)),
      ),
      const SizedBox(height: 14),
      Text('No trips yet', style: RideUi.title(context, size: 17)),
      const SizedBox(height: 4),
      Text('Your rides, parcels and bookings will appear here', textAlign: TextAlign.center, style: RideUi.caption(context, size: 13)),
    ]),
  );

  // Build the hire-driver booking summary from a REAL ride record.
  Widget _hireSummary(Map<String, dynamic> ride) {
    final id = ride['id']?.toString() ?? '';
    return HireDriverBookingDetailsScreen(
      inquiryId: id.length >= 6 ? 'HRD${id.substring(id.length - 6).toUpperCase()}' : 'HRD',
      pickupLocation: ride['from']?.toString() ?? '',
      dropLocation: ride['to']?.toString() ?? '',
      carType: (ride['vehicle']?.toString().isNotEmpty ?? false) ? ride['vehicle'].toString() : 'Car',
      hireDuration: '${ride['hireTotalHours'] ?? 0} hr',
      package: '${_hireDays(ride)} Day${_hireDays(ride) > 1 ? 's' : ''}',
      price: ride['fare']?.toString() ?? '₹0',
      tripStartDate: _isoDmy(ride['hireStartAt']) ?? _dateOnly(ride['date']),
      tripTime: _isoTime(ride['hireStartAt']) ?? (_timeOnly(ride['date']) ?? ''),
      tripEndDate: _isoDmy(ride['hireEndAt']),
      noOfDays: '${_hireDays(ride)}',
      tripType: ride['tripType']?.toString() ?? 'one_way',
      gearType: _gearLabel(ride['transmission']),
      visitingLocation: ride['to']?.toString() ?? '',
      bookingDate: _dateOnly(ride['date']),
      bookingTime: _timeOnly(ride['date']),
      driverName: ride['driver']?.toString(),
      vehicleModel: ride['driverVehicleModel']?.toString(),
      vehicleNumber: ride['driverVehicleNumber']?.toString(),
    );
  }

  String _dateOnly(dynamic d) {
    final s = d?.toString() ?? '';
    return s.contains(',') ? s.split(',')[0].trim() : s;
  }

  String? _timeOnly(dynamic d) {
    final s = d?.toString() ?? '';
    if (!s.contains(',')) return null;
    final parts = s.split(',')[1].trim().split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]) ?? 0;
    final ap = h >= 12 ? 'PM' : 'AM';
    final hh = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '${hh.toString().padLeft(2, '0')}:${parts[1]} $ap';
  }

  String? _isoDmy(dynamic iso) {
    final d = DateTime.tryParse(iso?.toString() ?? '')?.toLocal();
    if (d == null) return null;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  String? _isoTime(dynamic iso) {
    final d = DateTime.tryParse(iso?.toString() ?? '')?.toLocal();
    if (d == null) return null;
    final ap = d.hour >= 12 ? 'PM' : 'AM';
    final hh = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
    return '${hh.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} $ap';
  }

  int _hireDays(Map<String, dynamic> ride) {
    final s = DateTime.tryParse(ride['hireStartAt']?.toString() ?? '');
    final e = DateTime.tryParse(ride['hireEndAt']?.toString() ?? '');
    if (s != null && e != null) {
      final d = e.difference(s).inDays;
      if (d > 0) return d;
    }
    final hrs = (ride['hireTotalHours'] as int?) ?? 0;
    return hrs > 0 ? ((hrs + 23) ~/ 24) : 1;
  }

  String _gearLabel(dynamic t) {
    final s = (t ?? '').toString().toLowerCase();
    if (s.contains('auto')) return 'Automatic';
    if (s.contains('man')) return 'Manual';
    return s.isEmpty ? 'Manual' : t.toString();
  }

  static const _serviceIcons = <String, IconData>{
    'taxi': Icons.directions_car,
    'delivery': Icons.local_shipping_outlined,
    'rental': Icons.timer_outlined,
    'outstation': Icons.route,
    'hire_driver': Icons.person_pin_outlined,
  };

  static String _serviceName(String s) => switch (s) {
    'delivery' => 'Parcel',
    'rental' => 'Rental',
    'outstation' => 'Intercity',
    'hire_driver' => 'Hire driver',
    _ => 'Ride',
  };

  /// "28 Oct · 3:59 PM" from the ride's own timestamp.
  static String _when(Map<String, dynamic> ride) {
    final d = DateTime.tryParse((ride['createdAt'] ?? '').toString())?.toLocal();
    if (d == null) return (ride['date'] ?? '').toString();
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final now = DateTime.now();
    final day = '${d.day} ${m[d.month - 1]}${d.year != now.year ? ' ${d.year}' : ''}';
    return '$day · ${RideUi.clock(d)}';
  }

  /// The row title: where the trip went.
  static String historyTitle(Map<String, dynamic> ride) {
    final to = (ride['to'] ?? '').toString().trim();
    final from = (ride['from'] ?? '').toString().trim();
    final short = (to.isNotEmpty ? to : from).split(',').first.trim();
    switch (ride['service']) {
      case 'delivery':
        final who = (ride['receiverName'] ?? '').toString().trim();
        return who.isNotEmpty ? 'Parcel to $who' : (short.isNotEmpty ? 'Parcel to $short' : 'Parcel');
      case 'rental':
        final h = ride['packageHours'];
        return h is num && h > 0 ? 'Rental · $h hr' : 'Rental';
      case 'hire_driver':
        return short.isNotEmpty ? 'Driver hire · $short' : 'Driver hire';
      case 'outstation':
        final f = from.split(',').first.trim();
        return f.isNotEmpty && short.isNotEmpty ? '$f → $short' : (short.isNotEmpty ? short : 'Intercity');
    }
    return short.isNotEmpty ? short : 'Ride';
  }

  Widget _statusChip(String status) {
    final s = status.toLowerCase();
    final Color fg = s == 'completed'
        ? const Color(0xFF15803D)
        : s == 'cancelled' ? const Color(0xFFB91C1C) : RideUi.ink(context);
    final label = status.isEmpty ? '' : status[0].toUpperCase() + status.substring(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: fg.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
      child: Text(label, maxLines: 1, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg)),
    );
  }

  void _openDetail(Map<String, dynamic> ride) => Navigator.push(context, MaterialPageRoute(builder: (_) =>
      ride['service'] == 'hire_driver' ? _hireSummary(ride) : TripDetailScreen(ride: ride)));

  Widget _buildRideCard(Map<String, dynamic> ride) {
    final status = (ride['status'] ?? '').toString();
    final isCancelled = status == 'Cancelled';
    final isCompleted = status == 'Completed';
    final service = (ride['service'] ?? 'taxi').toString();
    final img = (ride['vehicleImageUrl'] ?? '').toString();
    final vehicle = (ride['vehicle'] ?? '').toString();
    final icon = _serviceIcons[service] ?? Icons.directions_car;
    return InkWell(
      key: ValueKey('trip-${ride['id']}'),
      borderRadius: BorderRadius.circular(RideUi.radius),
      onTap: () => _openDetail(ride),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(color: RideUi.tile(context), borderRadius: BorderRadius.circular(14)),
            child: img.isNotEmpty
                ? VehicleThumb(networkUrl: AppConfig.imageUrl(img), fallbackIcon: icon, size: 56)
                : Icon(icon, color: RideUi.ink(context), size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text(historyTitle(ride), maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: RideUi.body(context, size: 15, weight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                Text((ride['fare'] ?? '').toString(),
                    style: RideUi.body(context, size: 15, weight: FontWeight.w800)
                        .copyWith(decoration: isCancelled ? TextDecoration.lineThrough : null)),
              ]),
              const SizedBox(height: 3),
              Text(_when(ride), maxLines: 1, overflow: TextOverflow.ellipsis, style: RideUi.caption(context, size: 12.5)),
              const SizedBox(height: 2),
              Row(children: [
                Expanded(
                  child: Text([_serviceName(service), if (vehicle.isNotEmpty && service != 'hire_driver') vehicle].join(' · '),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: RideUi.caption(context, size: 12.5)),
                ),
                const SizedBox(width: 8),
                _statusChip(status),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (!isCancelled) _action(Icons.receipt_long_outlined, 'Invoice', () {
                  // The invoice renders this real ride (and refreshes it from GET /rides/:id).
                  Navigator.push(context, MaterialPageRoute(builder: (context) => InvoiceScreen(ride: ride)));
                }),
                if (!isCancelled && service != 'hire_driver') _action(Icons.route, 'Route', () => _showRouteReplay(ride)),
                // Rate — only when the ride is completed AND not yet rated
                if (isCompleted && ((ride['rating'] as double?) ?? 0) <= 0)
                  _action(Icons.star_border_rounded, 'Rate', () => Navigator.push(context, MaterialPageRoute(builder: (_) => RatingScreen(
                    driverName: (ride['driver'] as String?) ?? 'Driver',
                    vehicleName: (ride['vehicle'] as String?) ?? '',
                    selectedTip: 0,
                    rideId: ride['id'] as String?,
                  )))),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) => Material(
    color: RideUi.tile(context),
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: RideUi.ink(context)),
          const SizedBox(width: 4),
          Text(label, style: RideUi.body(context, size: 12, weight: FontWeight.w700)),
        ]),
      ),
    ),
  );
}
