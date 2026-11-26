import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/api_service.dart';
import 'vehicle_marker.dart';

/// Live vehicles of ONE service on a booking screen's map.
///
/// A parcel booking shows parcel vehicles, a rental shows rental cars — never
/// every cab in town. The server narrows /rides/nearby-drivers by `service` to
/// the vehicle types the admin enabled for it and drivers who opted in.
///
/// [serviceFleetCenter] returns where to look, or null while no map is on
/// screen (then nothing is fetched and the layer is empty).
mixin ServiceFleetMixin<T extends StatefulWidget> on State<T>, TickerProvider {
  AmbientVehicleFleet? _serviceFleet;
  Timer? _serviceFleetTimer;
  bool _serviceFleetBusy = false;

  /// The service whose vehicles are shown ('taxi', 'delivery', 'rental', 'outstation').
  String get fleetService;

  /// Where to look — null while the map is not showing.
  LatLng? serviceFleetCenter();

  // Exists from the start (before startServiceFleet), so a screen can build
  // its ValueListenableBuilder at any time.
  final ValueNotifier<Set<Marker>> _serviceFleetMarkers = ValueNotifier<Set<Marker>>(const <Marker>{});

  /// Markers to add to the GoogleMap, as of the last frame.
  Set<Marker> get serviceFleetMarkers => _serviceFleetMarkers.value;

  /// The fleet layer, updated every animation frame. Wrap ONLY the GoogleMap
  /// in a ValueListenableBuilder on it - the layer no longer calls setState on
  /// the whole booking screen every frame.
  ValueListenable<Set<Marker>> get serviceFleetListenable => _serviceFleetMarkers;

  void startServiceFleet() {
    _serviceFleet ??= AmbientVehicleFleet(vsync: this, onUpdate: () {
      if (mounted) _serviceFleetMarkers.value = _serviceFleet?.markers ?? const <Marker>{};
    });
    _serviceFleetTimer?.cancel();
    _serviceFleetTimer = Timer.periodic(const Duration(seconds: 5), (_) => refreshServiceFleet());
    refreshServiceFleet();
  }

  Future<void> refreshServiceFleet() async {
    final fleet = _serviceFleet;
    if (fleet == null || _serviceFleetBusy || !mounted) return;
    final c = serviceFleetCenter();
    if (c == null) { fleet.clear(); return; }
    _serviceFleetBusy = true;
    try {
      final drivers = await ApiService.getNearbyDrivers(c.latitude, c.longitude, radiusKm: 4, service: fleetService);
      if (!mounted) return;
      if (drivers.isEmpty) {
        fleet.clear();
      } else {
        await fleet.update(drivers);
      }
    } catch (_) {
      // Decoration only — never let it break booking.
    } finally {
      _serviceFleetBusy = false;
    }
  }

  /// Stops polling (screen covered or app in the background); markers stay.
  void pauseServiceFleet() {
    _serviceFleetTimer?.cancel();
    _serviceFleetTimer = null;
  }

  /// Polls again after [pauseServiceFleet]; a no-op if never started.
  void resumeServiceFleet() {
    if (_serviceFleet == null || _serviceFleetTimer != null) return;
    _serviceFleetTimer = Timer.periodic(const Duration(seconds: 5), (_) => refreshServiceFleet());
    refreshServiceFleet();
  }

  void disposeServiceFleet() {
    _serviceFleetTimer?.cancel();
    _serviceFleet?.dispose();
    _serviceFleet = null;
    _serviceFleetMarkers.dispose();
  }
}
