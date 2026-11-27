import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/driver_provider.dart';

// A higher-tier driver (Prime SUV) who switched on "Also take Cab, Prime Sedan
// rides" gets requests booked for those lower tiers of the same category. The
// rider pays the fare of the tier they booked and the driver earns from that
// fare, so the request card and the trip screen say which tier it is.

const _chipColor = Color(0xFF7C3AED);

/// "Cab ride · lower tier" when a ride booked for [rideVehicleType] is not
/// the driver's own [ownVehicleType]. Null when either is unknown or both are
/// the same type (case and spaces ignored).
String? lowerTierRideLabel(String rideVehicleType, String ownVehicleType) {
  final ride = rideVehicleType.trim();
  final own = ownVehicleType.trim();
  if (ride.isEmpty || own.isEmpty || ride.toLowerCase() == own.toLowerCase()) return null;
  return '$ride ride · lower tier';
}

/// The signed-in driver's own vehicle type (profile selectedVehicleTypeName),
/// '' when it is not known yet or there is no [DriverProvider] above.
String ownVehicleTypeOf(BuildContext context) {
  try {
    return Provider.of<DriverProvider>(context, listen: false).vehicleType;
  } catch (_) {
    return '';
  }
}

/// A small tinted pill with [label] ("Cab ride · lower tier").
class LowerTierChip extends StatelessWidget {
  final String label;
  const LowerTierChip(this.label, {super.key});

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$label. The fare is the fare of the type the rider booked.',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _chipColor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _chipColor.withValues(alpha: 0.35)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.layers_rounded, size: 15, color: _chipColor),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: _chipColor)),
            ),
          ]),
        ),
      );
}
