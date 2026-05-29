import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../services/location_service.dart';

// Fallback position — Ahmedabad
const _fallbackPos = LatLng(23.0225, 72.5714);

// ─── HOME MAP — live driver location ──────────────────────────
class MapPlaceholder extends StatefulWidget {
  const MapPlaceholder({super.key});
  @override
  State<MapPlaceholder> createState() => _MapPlaceholderState();
}

class _MapPlaceholderState extends State<MapPlaceholder> {
  GoogleMapController? _ctrl;
  LatLng _pos = _fallbackPos;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    final p = await LocationService.getCurrentLocation();
    if (p != null && mounted) {
      setState(() => _pos = LatLng(p.latitude, p.longitude));
      _ctrl?.animateCamera(CameraUpdate.newLatLng(_pos));
    }
  }

  @override
  void dispose() {
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
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      zoomControlsEnabled: true,
      mapToolbarEnabled: false,
      markers: {
        Marker(
          markerId: const MarkerId('driver'),
          position: _pos,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: 'You are here'),
        ),
      },
    );
  }
}

// ─── RIDE MAP — pickup + drop + route ─────────────────────────
class RideMap extends StatefulWidget {
  final double pickupLat, pickupLng, dropLat, dropLng;
  const RideMap({
    super.key,
    required this.pickupLat,
    required this.pickupLng,
    required this.dropLat,
    required this.dropLng,
  });
  @override
  State<RideMap> createState() => _RideMapState();
}

class _RideMapState extends State<RideMap> {
  GoogleMapController? _ctrl;

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  LatLng get _pickup => LatLng(widget.pickupLat, widget.pickupLng);
  LatLng get _drop   => LatLng(widget.dropLat,   widget.dropLng);
  LatLng get _center => LatLng(
    (widget.pickupLat + widget.dropLat) / 2,
    (widget.pickupLng + widget.dropLng) / 2,
  );

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      initialCameraPosition: CameraPosition(target: _center, zoom: 12),
      onMapCreated: (c) => _ctrl = c,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      markers: {
        Marker(
          markerId: const MarkerId('pickup'),
          position: _pickup,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(title: 'Pickup'),
        ),
        Marker(
          markerId: const MarkerId('drop'),
          position: _drop,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'Drop'),
        ),
      },
      polylines: {
        Polyline(
          polylineId: const PolylineId('route'),
          points: [_pickup, _drop],
          color: AppColors.primary,
          width: 4,
        ),
      },
    );
  }
}
