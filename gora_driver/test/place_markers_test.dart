import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'package:gora_driver/features/ride/widgets/place_markers.dart';

// #8 on the driver's side: the navigation map marks where the driver is going
// with the same glyphs the rider sees — a dot where someone is picked up, a
// square where they are dropped, a numbered disc for a stop. Every leg label a
// ride screen uses must land on the right one.

void main() {
  group('which glyph a leg gets', () {
    // Every label the on-ride screens pass to NavMapPanel today.
    const pickupLike = ['Pickup', 'Customer', 'Start point', 'pickup'];
    const dropLike = ['Drop', 'Receiver'];

    for (final label in pickupLike) {
      test('"$label" is a pickup', () {
        expect(PlaceMarkers.isPickupLike(label), isTrue);
        expect(PlaceMarkers.stopNumber(label), isNull);
        expect((PlaceMarkers.fallbackForLeg(label) as DefaultMarker).hue, BitmapDescriptor.hueGreen);
      });
    }

    for (final label in dropLike) {
      test('"$label" is a drop', () {
        expect(PlaceMarkers.isPickupLike(label), isFalse);
        expect(PlaceMarkers.stopNumber(label), isNull);
        expect((PlaceMarkers.fallbackForLeg(label) as DefaultMarker).hue, BitmapDescriptor.hueRed);
      });
    }

    test('"Stop 3" is stop number 3', () {
      expect(PlaceMarkers.stopNumber('Stop 3'), 3);
      expect(PlaceMarkers.stopNumber('Stop 12'), 12);
      expect((PlaceMarkers.fallbackForLeg('Stop 3') as DefaultMarker).hue, BitmapDescriptor.hueOrange);
    });
  });

  group('drawing', () {
    testWidgets('glyphs are drawn at their logical size', (tester) async {
      for (final g in await tester.runAsync(() => Future.wait([
            PlaceMarkers.pickup(2.0),
            PlaceMarkers.drop(2.0),
            PlaceMarkers.stop(2.0, 7),
          ])) ?? const <BitmapDescriptor>[]) {
        expect(g, isA<BytesMapBitmap>());
        expect((g as BytesMapBitmap).width, 30);
      }
    });

    testWidgets('each leg kind gets its own glyph', (tester) async {
      final glyphs = await tester.runAsync(() => Future.wait([
            PlaceMarkers.forLeg('Customer', 2.0),
            PlaceMarkers.forLeg('Receiver', 2.0),
            PlaceMarkers.forLeg('Stop 2', 2.0),
            PlaceMarkers.forLeg('Stop 3', 2.0),
          ]));
      expect(glyphs, hasLength(4));
      expect(identical(glyphs![0], glyphs[1]), isFalse, reason: 'A pickup must not look like a drop');
      expect(identical(glyphs[2], glyphs[3]), isFalse, reason: 'Each stop shows its own number');
      // Cached: the same leg kind reuses one bitmap.
      final again = await tester.runAsync(() => PlaceMarkers.forLeg('Pickup', 2.0));
      expect(identical(again, glyphs[0]), isTrue);
    });
  });
}
