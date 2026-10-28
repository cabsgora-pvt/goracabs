import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../utils/duration_format.dart';
import '../services/api_service.dart';
import '../utils/map_markers.dart';
import '../utils/vehicle_marker.dart';
import 'measure_size.dart';
import 'ride_ui/ride_ui.dart';

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
    // The status bar height. Shown as a bottom sheet, this view gets a
    // MediaQuery with the top padding removed, so SafeArea added nothing and
    // the chip sat on the clock — read the real inset from the window.
    final statusBar = math.max(media.padding.top, MediaQueryData.fromView(View.of(context)).padding.top);
    final topInset = statusBar + 60;   // clears the service chip
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
        Positioned(top: 0, left: 0, right: 0, child: Padding(
          padding: EdgeInsets.fromLTRB(12, statusBar + 12, 12, 12),
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
        )),
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
        // Bottom trip card (Uber style): bold title, indeterminate bar right
        // under it, then the trip summary and a quiet "Cancel Ride".
        Positioned(left: 0, right: 0, bottom: 0, child: MeasureSize(
          onChange: (s) { if (mounted && (s.height - _cardH).abs() > 1) setState(() => _cardH = s.height); },
          child: RideSheetContainer(
            radius: 24,
            child: SafeArea(top: false, child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const SheetHandle(bottom: 14),
                Row(children: [
                  Expanded(child: Text('Looking for nearby drivers', style: RideUi.title(context, size: 20))),
                  if (widget.etaMin != null) Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: RideUi.tile(context), borderRadius: BorderRadius.circular(20)),
                    child: Text('~${formatMinutes(widget.etaMin!)}', style: RideUi.body(context, size: 12, weight: FontWeight.w800))),
                ]),
                const SizedBox(height: 12),
                ClipRRect(borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(minHeight: 4, backgroundColor: RideUi.tile(context), valueColor: const AlwaysStoppedAnimation(_navy))),
                const SizedBox(height: 10),
                Text('Connecting you with nearby drivers', style: RideUi.caption(context, size: 12.5)),
                const RideDivider(vertical: 14),
                // Route: pickup → drop
                TripRouteSummary(
                  pickup: widget.pickupAddress.isEmpty ? 'Pickup' : widget.pickupAddress,
                  drop: widget.dropAddress,
                  fontSize: 13.5,
                ),
                const SizedBox(height: 14),
                // Vehicle + fare
                RideTile(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(children: [
                    Icon(widget.serviceIcon, size: 22, color: RideUi.ink(context)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(widget.vehicleType.isNotEmpty ? widget.vehicleType : widget.serviceLabel,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: RideUi.body(context, size: 14.5, weight: FontWeight.w800))),
                    if (widget.fareText != null) ...[
                      const SizedBox(width: 8),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                        Text('Estimated fare', style: RideUi.caption(context, size: 11)),
                        Text(widget.fareText!, style: RideUi.body(context, size: 17, weight: FontWeight.w900)),
                      ]),
                    ],
                  ]),
                ),
                const SizedBox(height: 6),
                RideTextAction(label: 'Cancel Ride', onPressed: widget.onCancel),
              ]),
            )),
          ),
        )),
      ]),
    );
  }
}
