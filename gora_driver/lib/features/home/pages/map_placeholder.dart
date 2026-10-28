import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../../../providers/driver_provider.dart';
import '../../../services/location_service.dart';
import '../../ride/widgets/nav_puck.dart';

// Fallback position — Ahmedabad
const _fallbackPos = LatLng(23.0225, 72.5714);

// ─── HOME MAP — live driver location ──────────────────────────
class MapPlaceholder extends StatefulWidget {
  /// Keeps Google's own controls (my-location) inside the part of the map not
  /// covered by the home screen's floating top bar and bottom sheet.
  final EdgeInsets padding;
  const MapPlaceholder({super.key, this.padding = EdgeInsets.zero});
  @override
  State<MapPlaceholder> createState() => _MapPlaceholderState();
}

class _MapPlaceholderState extends State<MapPlaceholder> {
  GoogleMapController? _ctrl;
  LatLng _pos = _fallbackPos;
  double _heading = 0;
  StreamSubscription<Position>? _sub;

  // The driver's own vehicle, as the rider will see it on their map. This was a
  // generic blue pin — the one place in the app a driver saw themselves as
  // something other than their vehicle.
  BitmapDescriptor? _vehicleIcon;
  String? _vehicleType;

  @override
  void initState() {
    super.initState();
    _initLocation();
    // Foreground only: while waiting for requests the marker should follow the
    // driver, but a background stream here would hold a location notification
    // up whenever the app is open. Navigation has its own background stream.
    _sub = LocationService.liveLocation(distanceFilter: 15).listen(_onPosition, onError: (_) {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    var type = '';
    try {
      // Provider.of, not context.watch: watch asserts it is called during build,
      // and on first mount didChangeDependencies runs before build.
      type = Provider.of<DriverProvider>(context).vehicleType;
    } catch (_) {/* no provider (a bare test harness): default sprite */}
    if (type == _vehicleType) return;
    _vehicleType = type;
    NavPuck.vehicle(type).then((ic) { if (mounted) setState(() => _vehicleIcon = ic); });
  }

  Future<void> _initLocation() async {
    final p = await LocationService.getCurrentLocation();
    if (p != null && mounted) {
      _onPosition(p);
      _ctrl?.animateCamera(CameraUpdate.newLatLng(_pos));
    }
  }

  void _onPosition(Position p) {
    if (!mounted) return;
    setState(() {
      _pos = LatLng(p.latitude, p.longitude);
      // A heading of 0 from a stationary fix is noise, not north.
      if (p.heading > 0 && p.speed > 1) _heading = p.heading;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      initialCameraPosition: CameraPosition(target: _pos, zoom: 15),
      onMapCreated: (c) {
        _ctrl = c;
        _ctrl?.animateCamera(CameraUpdate.newLatLng(_pos));
      },
      padding: widget.padding,
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      markers: {
        Marker(
          markerId: const MarkerId('driver'),
          position: _pos,
          rotation: _heading,
          flat: true,
          anchor: const Offset(0.5, 0.5),
          icon: _vehicleIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'You are here'),
        ),
      },
    );
  }
}


// NOTE: the old `RideMap` lived here. It drew a straight line between pickup
// and drop, never plotted the driver, and never showed an ETA. It is replaced
// by features/ride/widgets/nav_map.dart (NavMapPanel), which renders the real
// Directions polyline for the current leg. Do not reintroduce it.
