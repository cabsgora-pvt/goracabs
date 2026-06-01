import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../config/app_config.dart';
import '../theme/app_theme.dart';
import 'trip_detail_screen.dart';
import '../services/api_service.dart';
import '../utils/polyline_utils.dart';
import 'invoice_screen.dart';
import 'home_screen.dart';
import 'service_selection_screen.dart';
import 'rental_booking_details_screen.dart';
import 'hire_driver_booking_details_screen.dart';
import 'outstation_ride_details_screen.dart';
import 'rating_screen.dart';

class RideHistoryScreen extends StatefulWidget {
  const RideHistoryScreen({super.key});

  @override
  State<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

class _RideHistoryScreenState extends State<RideHistoryScreen> {
  int _currentIndex = 2;
  bool _isRideHistoryExpanded = false;
  bool _isRentalPackagesExpanded = false;
  bool _isHireDriverExpanded = false;
  bool _isOutstationExpanded = false;

  List<Map<String, dynamic>> _myRides = [];
  bool _loadingRides = true;

  @override
  void initState() {
    super.initState();
    _loadMyRides();
  }

  Future<void> _loadMyRides() async {
    try {
      final res = await ApiService.getMyRides();
      final list = (res['rides'] as List?) ?? [];
      setState(() {
        _myRides = list.map<Map<String, dynamic>>((r) {
          final svc = (r['service'] as String?) ?? 'taxi';
          final fare = (r['fare'] ?? 0);
          final tip = (r['tip'] ?? 0);
          final total = (r['totalFare'] ?? (fare + tip));
          final status = (r['status'] ?? '').toString();
          final dr = r['driver'] as Map<String, dynamic>?;
          final driverPic = (dr?['profilePicUrl'] ?? '').toString();
          return {
            'id': r['_id']?.toString() ?? '',
            'date': r['createdAt'] != null
                ? _formatDate(r['createdAt'].toString())
                : '',
            'from': r['pickupAddress'] ?? '',
            'to': r['dropAddress'] ?? '',
            'driver': (dr?['name'] ?? r['driverName'] ?? '—').toString(),
            'driverPic': driverPic.isEmpty ? '' : AppConfig.imageUrl(driverPic),
            'driverVehicleModel': (dr?['vehicleModel'] ?? '').toString(),
            'driverVehicleNumber': (dr?['vehicleNumber'] ?? '').toString(),
            'driverRatingVal': (dr?['rating'] as num?)?.toDouble() ?? 0,
            'fare': '₹$total',
            'baseFare': fare,
            'tip': tip,
            'total': total,
            'status': status == 'completed'
                ? 'Completed'
                : status == 'cancelled'
                    ? 'Cancelled'
                    : status,
            'rating': (r['driverRating'] ?? 0).toDouble(),
            'vehicle': r['vehicleType'] ?? '',
            'pickupLat': (r['pickupLat'] as num?)?.toDouble() ?? 0,
            'pickupLng': (r['pickupLng'] as num?)?.toDouble() ?? 0,
            'dropLat': (r['dropLat'] as num?)?.toDouble() ?? 0,
            'dropLng': (r['dropLng'] as num?)?.toDouble() ?? 0,
            'routePolyline': (r['routePolyline'] as String?) ?? '',
            'service': svc,
            'tripType': (r['tripType'] as String?) ?? 'one_way',
            'numPassengers': (r['numPassengers'] as num?)?.toInt() ?? 0,
            'duration': (r['duration'] as num?)?.toInt() ?? 0,
            'distance': (r['distance'] as num?)?.toDouble() ?? 0,
            'paymentMode': (r['paymentMode'] ?? 'cash').toString(),
            'vehicleImageUrl': (r['vehicleImageUrl'] as String?) ?? '',
            // Rental extras
            'packageHours': (r['packageHours'] as num?)?.toInt() ?? 0,
            'packageKm': (r['packageKm'] as num?)?.toInt() ?? 0,
            'actualHours': (r['actualHours'] as num?)?.toDouble() ?? 0,
            'actualKm': (r['actualKm'] as num?)?.toDouble() ?? 0,
            'extraHoursCharge': (r['extraHoursCharge'] as num?)?.toInt() ?? 0,
            'extraKmCharge': (r['extraKmCharge'] as num?)?.toInt() ?? 0,
            'nightChargeRental': (r['nightChargeRental'] as num?)?.toInt() ?? 0,
            'finalFare': (r['finalFare'] as num?)?.toInt() ?? 0,
            // Outstation extras
            'nightHaltCharge': (r['nightHaltCharge'] as num?)?.toInt() ?? 0,
            'emptyReturnCharge': (r['emptyReturnCharge'] as num?)?.toInt() ?? 0,
            'tollCharge': (r['tollCharge'] as num?)?.toInt() ?? 0,
            // Hire extras
            'hireTotalHours': (r['hireTotalHours'] as num?)?.toInt() ?? 0,
            'hirePerHour': (r['hirePerHour'] as num?)?.toInt() ?? 0,
            'transmission': (r['transmission'] ?? '').toString(),
            'hireStartAt': (r['hireStartAt'] ?? '').toString(),
            'hireEndAt': (r['hireEndAt'] ?? '').toString(),
          };
        }).toList();
        _loadingRides = false;
      });
    } catch (_) {
      setState(() => _loadingRides = false);
    }
  }

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
      backgroundColor: Colors.white,
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
                child: GoogleMap(
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
                    Marker(markerId: const MarkerId('pickup'), position: pickup, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen), infoWindow: InfoWindow(title: 'Pickup', snippet: ride['from']?.toString())),
                    Marker(markerId: const MarkerId('drop'),   position: drop,   icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),   infoWindow: InfoWindow(title: 'Drop',   snippet: ride['to']?.toString())),
                  },
                  polylines: {
                    Polyline(polylineId: const PolylineId('route'), points: pts, color: AppTheme.primaryBlue, width: 5),
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.grey[50], border: Border(top: BorderSide(color: Colors.grey[200]!))),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip Details', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: true,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.black),
        ),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildExpandableSection(
              'Ride History',
              Icons.directions_car,
              _isRideHistoryExpanded,
              () => setState(() => _isRideHistoryExpanded = !_isRideHistoryExpanded),
              _buildRideHistoryList(),
            ),
            const SizedBox(height: 16),
            _buildExpandableSection(
              'Rental Packages',
              Icons.schedule,
              _isRentalPackagesExpanded,
              () => setState(() => _isRentalPackagesExpanded = !_isRentalPackagesExpanded),
              _buildRentalPackagesList(),
            ),
            const SizedBox(height: 16),
            _buildExpandableSection(
              'Hire Driver',
              Icons.person,
              _isHireDriverExpanded,
              () => setState(() => _isHireDriverExpanded = !_isHireDriverExpanded),
              _buildHireDriverList(),
            ),
            const SizedBox(height: 16),
            _buildExpandableSection(
              'Outstation',
              Icons.location_on,
              _isOutstationExpanded,
              () => setState(() => _isOutstationExpanded = !_isOutstationExpanded),
              _buildOutstationList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandableSection(String title, IconData icon, bool isExpanded, VoidCallback onTap, Widget content) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(icon, color: AppTheme.primaryBlue, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: Colors.grey[600],
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            content,
          ],
        ],
      ),
    );
  }

  Widget _buildRideHistoryList() {
    if (_loadingRides) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    final rides = _myRides.where((r) => r['service'] == 'taxi').toList();
    if (rides.isEmpty) return const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No taxi rides yet', style: TextStyle(color: Colors.grey))));
    return Column(children: rides.map((r) => _buildRideCard(r)).toList());
  }

  Widget _buildRentalPackagesList() {
    if (_loadingRides) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    final rentals = _myRides.where((r) => r['service'] == 'rental').toList();
    if (rentals.isEmpty) return const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No rental bookings yet', style: TextStyle(color: Colors.grey))));
    // Reuse the unified ride card (shows driver pic + vehicle + rating)
    return Column(children: rentals.map((r) => _buildRideCard(r)).toList());
  }

  Widget _buildHireDriverList() {
    if (_loadingRides) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    final hires = _myRides.where((r) => r['service'] == 'hire_driver').toList();
    if (hires.isEmpty) return const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No hire-driver bookings yet', style: TextStyle(color: Colors.grey))));
    // Unified card → tap opens full detail (real driver, vehicle, price, hours)
    return Column(children: hires.map((r) => _buildRideCard(r)).toList());
  }

  Widget _buildOutstationList() {
    if (_loadingRides) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    final outs = _myRides.where((r) => r['service'] == 'outstation').toList();
    if (outs.isEmpty) return const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No outstation trips yet', style: TextStyle(color: Colors.grey))));
    // Reuse the unified ride card (shows driver pic + vehicle + rating + route)
    return Column(children: outs.map((r) => _buildRideCard(r)).toList());
  }

  Widget _buildRideCard(Map<String, dynamic> ride) {
    final isCancelled = ride['status'] == 'Cancelled';
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TripDetailScreen(ride: ride))),
      child: Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isCancelled ? Colors.red[50] : Colors.green[50],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  ride['status'] as String,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isCancelled ? Colors.red : Colors.green,
                  ),
                ),
              ),
              const Spacer(),
              Text(ride['date'] as String, style: const TextStyle(fontSize: 11, color: AppTheme.textGrey)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Column(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Container(
                    width: 2,
                    height: 20,
                    color: Colors.grey[300],
                  ),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ride['from'] as String, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 16),
                    Text(ride['to'] as String, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Text(ride['fare'] as String, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
            ],
          ),
          // Driver row — pic + name + vehicle (real data for all service types)
          if ((ride['driver'] as String?) != null && ride['driver'] != '—') ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppTheme.primaryBlue.withOpacity(0.1),
                backgroundImage: (ride['driverPic'] as String).isNotEmpty ? NetworkImage(ride['driverPic'] as String) : null,
                child: (ride['driverPic'] as String).isEmpty
                    ? Text((ride['driver'] as String).isNotEmpty ? (ride['driver'] as String)[0].toUpperCase() : 'D',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue))
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(ride['driver'] as String, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                Text(
                  [ride['driverVehicleModel'], ride['driverVehicleNumber']].where((s) => (s as String).isNotEmpty).join(' • '),
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]), maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ])),
              if ((ride['driverRatingVal'] as double) > 0) Row(children: [
                const Icon(Icons.star, size: 13, color: Colors.amber),
                const SizedBox(width: 2),
                Text((ride['driverRatingVal'] as double).toStringAsFixed(1), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
            ]),
          ],
          if (!isCancelled) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => _showRouteReplay(ride),
                    icon: const Icon(Icons.route, size: 14),
                    label: const Text('Show Route', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(foregroundColor: AppTheme.primaryBlue),
                  ),
                ),
                // Rate button — only when ride is completed AND not yet rated
                if (((ride['rating'] as double?) ?? 0) <= 0)
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RatingScreen(
                        driverName: (ride['driver'] as String?) ?? 'Driver',
                        vehicleName: (ride['vehicle'] as String?) ?? '',
                        selectedTip: 0,
                        rideId: ride['id'] as String?,
                      ))),
                      icon: const Icon(Icons.star_rate, size: 14, color: Colors.amber),
                      label: const Text('Rate', style: TextStyle(fontSize: 12, color: Colors.amber)),
                      style: TextButton.styleFrom(foregroundColor: Colors.amber),
                    ),
                  ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () {
                      final String originalVehicle = (ride['vehicle'] as String?) ?? '';
                      final String mappedVehicle = originalVehicle == 'Gora Go'
                          ? 'Bike'
                          : originalVehicle == 'Gora Sedan'
                              ? 'Cab Economy'
                              : originalVehicle == 'Gora SUV'
                                  ? 'SUV'
                                  : originalVehicle.isNotEmpty
                                      ? originalVehicle
                                      : 'Cab Economy';
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => InvoiceScreen(
                            vehicleName: mappedVehicle,
                            selectedTip: (ride['tip'] as int?) ?? 0,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.receipt_long, size: 14),
                    label: const Text('Invoice', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(foregroundColor: AppTheme.primaryBlue),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      ),
    );
  }

  Widget _buildRentalCard(Map<String, dynamic> rental) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.schedule, color: AppTheme.primaryBlue, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(rental['package'] as String, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    Text('${rental['vehicle']} • ${rental['duration']}', style: const TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                    Text(rental['date'] as String, style: const TextStyle(fontSize: 11, color: AppTheme.textGrey)),
                  ],
                ),
              ),
              Text(rental['fare'] as String, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RentalBookingDetailsScreen(
                          inquiryId: 'RNT${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}',
                          pickupLocation: 'MG Road, Delhi',
                          dropLocation: 'Cyber City, Gurugram',
                          duration: rental['duration'] as String,
                          vehicle: rental['vehicle'] as String,
                          price: rental['fare'] as String,
                          date: rental['date'] as String,
                          time: '9:00 AM',
                          driverName: 'Suresh Kumar',
                          driverRating: '4.9 (1.2k+ trips)',
                          driverExperience: '8 years experience',
                          vehicleNumber: 'DL 01 AB 1234',
                          vehicleModel: 'Maruti Swift Dzire',
                          vehicleColor: 'White',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.info_outline, size: 14),
                  label: const Text('Details', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.primaryBlue),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => InvoiceScreen(
                          vehicleName: rental['vehicle'] as String,
                          selectedTip: 0,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.receipt_long, size: 14),
                  label: const Text('Invoice', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.primaryBlue),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHireDriverCard(Map<String, dynamic> hire) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.person, color: AppTheme.primaryBlue, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Driver: ${hire['driver']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    Text('Duration: ${hire['duration']}', style: const TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                    Text(hire['date'] as String, style: const TextStyle(fontSize: 11, color: AppTheme.textGrey)),
                  ],
                ),
              ),
              Text(hire['fare'] as String, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => HireDriverBookingDetailsScreen(
                          inquiryId: 'HRD${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}',
                          pickupLocation: 'MG Road, Delhi',
                          dropLocation: 'Cyber City, Gurugram',
                          carType: 'Sedan',
                          hireDuration: hire['duration'] as String,
                          package: '1 Day',
                          price: hire['fare'] as String,
                          tripStartDate: hire['date'] as String,
                          tripTime: '2:00 PM',
                          driverName: hire['driver'] as String,
                          driverRating: '4.8 (500+ trips)',
                          driverExperience: '5 years experience',
                          vehicleNumber: 'DL 03 CD 9876',
                          vehicleModel: 'Honda City',
                          vehicleColor: 'White',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.info_outline, size: 14),
                  label: const Text('Details', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.primaryBlue),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => InvoiceScreen(
                          vehicleName: 'Hire Driver',
                          selectedTip: 0,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.receipt_long, size: 14),
                  label: const Text('Invoice', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.primaryBlue),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOutstationCard(Map<String, dynamic> outstation) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.location_on, color: AppTheme.primaryBlue, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${outstation['from']} → ${outstation['to']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    Text('${outstation['vehicle']} • ${outstation['driver']}', style: const TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                    Text(outstation['date'] as String, style: const TextStyle(fontSize: 11, color: AppTheme.textGrey)),
                  ],
                ),
              ),
              Text(outstation['fare'] as String, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => OutstationRideDetailsScreen(
                          inquiryId: 'OUT${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}',
                          fromLocation: outstation['from'] as String,
                          toLocation: outstation['to'] as String,
                          vehicleName: outstation['vehicle'] as String,
                          vehicleType: 'Premium',
                          capacity: '6',
                          tripType: 'One Way',
                          departureDate: outstation['date'] as String,
                          departureTime: '6:00 AM',
                          price: outstation['fare'] as String,
                          estimatedDistance: '~250 km',
                          estimatedDuration: '~5 hours',
                          driverName: outstation['driver'] as String,
                          driverRating: '4.8 (2.5k+ trips)',
                          driverExperience: '10 years experience',
                          vehicleNumber: 'RJ 14 AB 5678',
                          vehicleModel: 'Toyota Innova Crysta',
                          vehicleColor: 'Silver',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.info_outline, size: 14),
                  label: const Text('Details', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.primaryBlue),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => InvoiceScreen(
                          vehicleName: outstation['vehicle'] as String,
                          selectedTip: 0,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.receipt_long, size: 14),
                  label: const Text('Invoice', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.primaryBlue),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showRentalDetails(Map<String, dynamic> rental) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.schedule, color: AppTheme.primaryBlue),
              const SizedBox(width: 8),
              const Text('Rental Package Details'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('Package', rental['package'] as String),
              _buildDetailRow('Vehicle', rental['vehicle'] as String),
              _buildDetailRow('Duration', rental['duration'] as String),
              _buildDetailRow('Date & Time', rental['date'] as String),
              _buildDetailRow('Status', rental['status'] as String),
              _buildDetailRow('Total Fare', rental['fare'] as String),
              const SizedBox(height: 16),
              const Text('Package Includes:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('• Unlimited stops within package duration'),
              const Text('• Fixed pricing, no surge charges'),
              const Text('• Professional driver'),
              const Text('• Fuel included'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showHireDriverDetails(Map<String, dynamic> hire) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.person, color: AppTheme.primaryBlue),
              const SizedBox(width: 8),
              const Text('Hire Driver Details'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('Driver Name', hire['driver'] as String),
              _buildDetailRow('Duration', hire['duration'] as String),
              _buildDetailRow('Date & Time', hire['date'] as String),
              _buildDetailRow('Status', hire['status'] as String),
              _buildDetailRow('Total Fare', hire['fare'] as String),
              const SizedBox(height: 16),
              const Text('Service Includes:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('• Experienced professional driver'),
              const Text('• Your own vehicle usage'),
              const Text('• Flexible timing'),
              const Text('• Multiple stops allowed'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showOutstationDetails(Map<String, dynamic> outstation) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.location_on, color: AppTheme.primaryBlue),
              const SizedBox(width: 8),
              const Text('Outstation Trip Details'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('From', outstation['from'] as String),
              _buildDetailRow('To', outstation['to'] as String),
              _buildDetailRow('Vehicle', outstation['vehicle'] as String),
              _buildDetailRow('Driver', outstation['driver'] as String),
              _buildDetailRow('Date & Time', outstation['date'] as String),
              _buildDetailRow('Status', outstation['status'] as String),
              _buildDetailRow('Total Fare', outstation['fare'] as String),
              const SizedBox(height: 16),
              const Text('Trip Includes:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('• Round trip or one-way available'),
              const Text('• Professional intercity driver'),
              const Text('• Fuel and toll charges included'),
              const Text('• 24/7 customer support'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class RatingDialog extends StatefulWidget {
  final String driver;
  const RatingDialog({super.key, required this.driver});

  @override
  State<RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<RatingDialog> {
  int _rating = 0;
  final _feedbackController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Rate ${widget.driver}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              return IconButton(
                onPressed: () => setState(() => _rating = i + 1),
                icon: Icon(
                  i < _rating ? Icons.star : Icons.star_border,
                  color: Colors.amber,
                  size: 36,
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _feedbackController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Share your feedback (optional)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _rating == 0
              ? null
              : () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Thank you for your feedback!')),
                  );
                },
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
          child: const Text('Submit', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}