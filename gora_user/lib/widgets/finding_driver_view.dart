import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/api_service.dart';
import '../utils/map_markers.dart';
import '../utils/vehicle_marker.dart';
import 'measure_size.dart';

// "Looking for a driver" full-screen view: the pickup with a searching radar
// over it, real nearby vehicles of the type being booked, the trip summary and
// a Cancel button. Parent keeps polling and pops this on accept; [onCancel] runs
// the parent's cancel-with-reason flow.
//
// It used to frame pickup and drop together, join them with a STRAIGHT line
// that read as the route but crossed buildings and rivers, and mark both with
// Google's default pins — while the live ride screen already had the radar and
// flat markers. Taxi, the service booked most, searched on the plainer screen.
class FindingDriverView extends StatefulWidget {
  final double pickupLat, pickupLng;
  final double? dropLat, dropLng;
  final String pickupAddress, dropAddress;
  final String? fareText;       // e.g. "₹540"
  final String serviceLabel;
  final IconData serviceIcon;
  final int? etaMin;
  final VoidCallback onCancel;
  /// The vehicle type being booked, so the vehicles shown nearby are the kind
  /// that could actually be assigned. Empty shows every type.
  final String vehicleType;
  const FindingDriverView({
    super.key,
    required this.pickupLat,
    required this.pickupLng,
    required this.serviceLabel,
    required this.serviceIcon,
    required this.onCancel,
    this.dropLat,
    this.dropLng,
    this.pickupAddress = '',
    this.dropAddress = '',
    this.fareText,
    this.etaMin,
    this.vehicleType = '',
  });

  @override
  State<FindingDriverView> createState() => _FindingDriverViewState();
}

class _FindingDriverViewState extends State<FindingDriverView>
    with SingleTickerProviderStateMixin {
  static const Color _navy = Color(0xFF1C2656);
  static const double _radar = 220;

  GoogleMapController? _ctrl;
  late final AmbientVehicleFleet _fleet;
  Timer? _nearbyTimer;

  // Height of the trip card, so the camera centres the pickup — and the radar
  // sits on it — in the part of the map the card does not cover.
  double _cardH = 320;

  // Following the pickup until the rider pans. Pointers, not camera callbacks:
  // our own animateCamera fires onCameraMoveStarted too.
  bool _following = true;
  int _mapPointers = 0;

  LatLng get _pickup => LatLng(widget.pickupLat, widget.pickupLng);

  @override
  void initState() {
    super.initState();
    _fleet = AmbientVehicleFleet(
      vsync: this,
      duration: const Duration(seconds: 4),
      onUpdate: () { if (mounted) setState(() {}); },
    );
    _loadNearby();
    _nearbyTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadNearby());
  }

  @override
  void dispose() {
    _nearbyTimer?.cancel();
    _fleet.dispose();
    super.dispose();
  }

  /// Real available drivers around the pickup, of the booked type.
  Future<void> _loadNearby() async {
    try {
      final drivers = await ApiService.getNearbyDrivers(
        widget.pickupLat, widget.pickupLng,
        radiusKm: 3,
        vehicleType: widget.vehicleType.isEmpty ? null : widget.vehicleType,
      );
      if (!mounted) return;
      if (drivers.isEmpty) {
        _fleet.clear();
      } else {
        await _fleet.update(drivers);
      }
    } catch (_) {/* decoration only — never let it break the search */}
  }

  void _centerOnPickup() =>
      _ctrl?.animateCamera(CameraUpdate.newLatLngZoom(_pickup, 16));

  void _recenter() {
    _mapPointers = 0;
    setState(() => _following = true);
    _centerOnPickup();
  }

  @override
  Widget build(BuildContext context) {
    final hasDrop = widget.dropLat != null && widget.dropLng != null;
    final media = MediaQuery.of(context);
    final topInset = media.padding.top + 60;   // clears the service chip
    final visibleH = (media.size.height - topInset - _cardH).clamp(0.0, double.infinity);

    return Scaffold(
      body: Stack(children: [
        Positioned.fill(child: Listener(
          onPointerDown: (_) => _mapPointers++,
          onPointerUp: (_) => _mapPointers = _mapPointers > 0 ? _mapPointers - 1 : 0,
          onPointerCancel: (_) => _mapPointers = _mapPointers > 0 ? _mapPointers - 1 : 0,
          child: PlaceGlyphs(builder: (context, glyphs) => GoogleMap(
            initialCameraPosition: CameraPosition(target: _pickup, zoom: 16),
            onMapCreated: (c) { _ctrl = c; _centerOnPickup(); },
            onCameraMoveStarted: () {
              if (_mapPointers > 0 && _following) setState(() => _following = false);
            },
            zoomControlsEnabled: false,
            myLocationButtonEnabled: false,
            // Centres the camera target in the visible band between the chip and
            // the card, which is exactly where the radar is drawn.
            padding: EdgeInsets.only(top: topInset, bottom: _cardH),
            markers: {
              ..._fleet.markers,
              Marker(
                markerId: const MarkerId('p'),
                position: _pickup,
                anchor: glyphs.pickupAnchor,
                icon: glyphs.pickup,
                zIndexInt: 2,
              ),
              if (hasDrop)
                Marker(
                  markerId: const MarkerId('d'),
                  position: LatLng(widget.dropLat!, widget.dropLng!),
                  anchor: glyphs.dropAnchor,
                  icon: glyphs.drop,
                  zIndexInt: 2,
                ),
            },
          )),
        )),
        // Searching radar, over the pickup. Hidden once the rider pans, when it
        // would no longer sit on the pin.
        if (_following)
          Positioned(
            left: media.size.width / 2 - _radar / 2,
            top: topInset + visibleH / 2 - _radar / 2,
            child: const SearchRadar(size: _radar),
          ),
        // Service chip (top)
        Positioned(top: 0, left: 0, right: 0, child: SafeArea(child: Padding(
          padding: const EdgeInsets.all(12),
          child: Align(alignment: Alignment.centerLeft, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 6)]),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(widget.serviceIcon, size: 16, color: _navy),
              const SizedBox(width: 8),
              Flexible(child: Text(widget.serviceLabel,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
            ]),
          )),
        ))),
        if (!_following)
          Positioned(
            right: 14,
            bottom: _cardH + 14,
            child: Material(
              color: Theme.of(context).cardColor,
              elevation: 4,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _recenter,
                child: const SizedBox(width: 48, height: 48,
                  child: Tooltip(message: 'Back to pickup', child: Icon(Icons.my_location, color: _navy))),
              ),
            ),
          ),
        // Bottom trip card
        Positioned(left: 0, right: 0, bottom: 0, child: MeasureSize(
          onChange: (s) { if (mounted && (s.height - _cardH).abs() > 1) setState(() => _cardH = s.height); },
          child: Container(
          decoration: BoxDecoration(color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 16, offset: const Offset(0, -4))]),
          child: SafeArea(top: false, child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Heading + thin progress bar (the radar carries the motion)
              Row(children: [
                const Expanded(child: Text('Looking for a driver', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900))),
                if (widget.etaMin != null) Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: _navy.withOpacity(0.08), borderRadius: BorderRadius.circular(20)),
                  child: Text('~${widget.etaMin} min', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _navy))),
              ]),
              const SizedBox(height: 4),
              Text('Connecting you with nearby drivers', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              const SizedBox(height: 12),
              ClipRRect(borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(minHeight: 4, backgroundColor: _navy.withOpacity(0.10), valueColor: const AlwaysStoppedAnimation(_navy))),
              const SizedBox(height: 16),
              // Route: pickup → drop
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.grey.withOpacity(0.06), borderRadius: BorderRadius.circular(12)),
                child: Column(children: [
                  Row(children: [
                    const Icon(Icons.radio_button_checked, size: 15, color: Color(0xFF4CAF50)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(widget.pickupAddress.isEmpty ? 'Pickup' : widget.pickupAddress,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                  ]),
                  if (widget.dropAddress.isNotEmpty) ...[
                    Padding(padding: const EdgeInsets.only(left: 6), child: Align(alignment: Alignment.centerLeft,
                      child: Container(width: 2, height: 16, color: Colors.grey[300]))),
                    Row(children: [
                      const Icon(Icons.location_on, size: 15, color: Color(0xFFFF5252)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(widget.dropAddress, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                    ]),
                  ],
                ]),
              ),
              if (widget.fareText != null) ...[
                const SizedBox(height: 12),
                Row(children: [
                  const Expanded(child: Text('Estimated fare', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                  Text(widget.fareText!, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _navy)),
                ]),
              ],
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: OutlinedButton.icon(
                onPressed: widget.onCancel,
                icon: const Icon(Icons.close, size: 18, color: Colors.red),
                label: const Text('Cancel Ride', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w800, fontSize: 15)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red), padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              )),
            ]),
          )),
        ))),
      ]),
    );
  }
}
