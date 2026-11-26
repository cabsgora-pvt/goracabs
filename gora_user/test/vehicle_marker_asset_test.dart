import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/utils/vehicle_marker.dart';

void main() {
  const top = 'assets/images/topview';

  test('live vehicle types map to their own sprite', () {
    // The six types configured in production (2026-11-26).
    expect(VehicleMarkers.assetFor('Bike'), '$top/bike-captain-top.png');
    expect(VehicleMarkers.assetFor('Auto'), '$top/auto-top.png');
    expect(VehicleMarkers.assetFor('Cab'), '$top/economy-top.png');
    expect(VehicleMarkers.assetFor('Prime Sedan'), '$top/primium-top.png');
    expect(VehicleMarkers.assetFor('Prime SUV'), '$top/suv-top.png');
    expect(VehicleMarkers.assetFor('Mini Truck'), '$top/tempo-top.png');
  });

  test('other names admins use', () {
    expect(VehicleMarkers.assetFor('Tempo'), '$top/tempo-top.png');
    expect(VehicleMarkers.assetFor('Tata Ace'), '$top/tempo-top.png');
    expect(VehicleMarkers.assetFor('Loader'), '$top/tempo-top.png');
    expect(VehicleMarkers.assetFor('Bike Lite'), '$top/bike-captain-top.png');
    expect(VehicleMarkers.assetFor('Scooty'), '$top/scooter-top.png');
    expect(VehicleMarkers.assetFor('E-Rickshaw'), '$top/auto-top.png');
    expect(VehicleMarkers.assetFor('EV Auto'), '$top/ev-auto-top.png');
    // "ace" only as a word: a name merely containing the letters stays a car.
    expect(VehicleMarkers.assetFor('Space Cab'), '$top/economy-top.png');
    expect(VehicleMarkers.assetFor(''), '$top/economy-top.png');
  });

  test('every sprite the mapping can return is bundled', () {
    for (final n in ['Bike', 'Auto', 'EV Auto', 'Cab', 'Prime Sedan', 'Prime SUV', 'Mini Truck', 'Scooty']) {
      expect(File(VehicleMarkers.assetFor(n)).existsSync(), isTrue, reason: n);
    }
  });
}
