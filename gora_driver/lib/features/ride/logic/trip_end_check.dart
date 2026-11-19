import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../models/models.dart';
import '../widgets/nav_engine.dart';

/// Beyond this, ending an outstation trip needs the driver's explicit say-so.
const earlyEndKm = 10.0;

/// How far [here] is from where an outstation trip should finish — the drop,
/// or the start point on a round trip. Null for other services or with no fix.
double? kmFromTripEnd(RideRequestModel r, LatLng? here) {
  if (r.service != 'outstation' || here == null) return null;
  final round = r.tripType == 'round_trip';
  final end = round ? LatLng(r.pickupLat, r.pickupLng) : LatLng(r.dropLat, r.dropLng);
  return metersBetween(here, end) / 1000;
}
