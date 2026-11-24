import 'package:flutter/material.dart';
import '../../../config/app_config.dart';
import '../../../widgets/captain_ui/captain_ui.dart';

/// Bundled side-view photo for a vehicle type [name] (case-insensitive):
/// bike/scooter → bike, auto/rickshaw → auto, mini truck/truck/tempo →
/// mini-truck, suv → prime-suv, sedan/prime → prime-sedan, anything else → cab.
String vehicleAssetFor(String name) {
  final s = name.toLowerCase();
  const dir = 'assets/images/vehicles';
  if (s.contains('bike') || s.contains('scooter') || s.contains('moto')) return '$dir/bike.webp';
  if (s.contains('auto') || s.contains('rickshaw')) return '$dir/auto.webp';
  if (s.contains('truck') || s.contains('tempo')) return '$dir/mini-truck.webp';
  if (s.contains('suv')) return '$dir/prime-suv.webp';
  if (s.contains('sedan') || s.contains('prime')) return '$dir/prime-sedan.webp';
  return '$dir/cab.webp';
}

/// Last-resort icon for a vehicle type, when even the bundled photo fails.
IconData vehicleIconFor(String name) {
  final s = name.toLowerCase();
  if (s.contains('bike') || s.contains('moto') || s.contains('scooter')) return Icons.two_wheeler;
  if (s.contains('auto') || s.contains('rickshaw')) return Icons.electric_rickshaw;
  if (s.contains('truck') || s.contains('tempo')) return Icons.local_shipping;
  if (s.contains('suv')) return Icons.airport_shuttle;
  return Icons.directions_car_rounded;
}

/// Display label for a service key from GET /api/vehicles/types.
String vehicleServiceLabel(String key) => switch (key.trim().toLowerCase()) {
      'taxi' => 'Taxi',
      'rental' => 'Rental',
      'outstation' => 'Outstation',
      'parcel' || 'delivery' => 'Parcel',
      'hire_driver' || 'hire' || 'driver_hire' => 'Hire driver',
      final k when k.isEmpty => '',
      final k => (k[0].toUpperCase() + k.substring(1)).replaceAll('_', ' '),
    };

/// Accent colour for a service chip.
Color vehicleServiceColor(String key) => switch (key.trim().toLowerCase()) {
      'taxi' => const Color(0xFF0A3CC8),
      'rental' => const Color(0xFF7C3AED),
      'outstation' => const Color(0xFF0D9488),
      'parcel' || 'delivery' => const Color(0xFFEA6A00),
      'hire_driver' || 'hire' || 'driver_hire' => const Color(0xFFDB2777),
      _ => const Color(0xFF475569),
    };

/// The vehicle type's real photo, in this order:
///   1. the admin-uploaded network image (`imageUrl`, via [AppConfig.imageUrl]);
///   2. the bundled photo matched by name ([vehicleAssetFor]) — also shown
///      while the network image loads and if it fails;
///   3. an icon, only if the bundled photo cannot load either.
class VehicleTypeImage extends StatelessWidget {
  final Map<String, dynamic> vt;
  final double width, height;
  const VehicleTypeImage({super.key, required this.vt, this.width = 84, this.height = 64});

  /// Kept for callers of the old helper.
  static IconData iconFor(String name) => vehicleIconFor(name);

  @override
  Widget build(BuildContext context) {
    final name = (vt['name'] ?? '').toString();
    final raw = (vt['imageUrl'] as String? ?? '').trim();
    final url = raw.isEmpty ? '' : AppConfig.imageUrl(raw);
    final asset = Image.asset(
      vehicleAssetFor(name),
      key: const ValueKey('vehicle_asset'),
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Center(
        key: const ValueKey('vehicle_icon'),
        child: Icon(vehicleIconFor(name), size: height * 0.55, color: Cap.muted),
      ),
    );
    return SizedBox(
      width: width,
      height: height,
      child: url.isEmpty
          ? asset
          : Image.network(
              url,
              key: const ValueKey('vehicle_network'),
              fit: BoxFit.contain,
              // Until the first frame arrives, the bundled photo stands in.
              frameBuilder: (_, child, frame, sync) => frame == null && !sync ? asset : child,
              errorBuilder: (_, __, ___) => asset,
            ),
    );
  }
}
