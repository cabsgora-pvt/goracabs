import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gora_driver/features/ride/widgets/ride_status_strip.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Layout-overflow tests.
//
// `flutter analyze` and `flutter build` cannot see a RenderFlex overflow — it
// happens during layout, at runtime, on a real screen size. The test framework
// CAN see it: an overflowing Row/Column reports a FlutterError during the frame,
// which `tester.takeException()` returns.
//
// So these pump the widgets at the sizes that actually break things — a small
// phone, and long real-world content — rather than trusting that they looked
// fine on one device.
// ─────────────────────────────────────────────────────────────────────────────

/// Pumps [child] at a fixed logical size and fails if layout overflowed.
Future<void> expectNoOverflow(
  WidgetTester tester,
  Widget child, {
  required Size size,
  required String label,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: Center(child: child)),
  ));
  await tester.pump();

  final err = tester.takeException();
  expect(err, isNull, reason: 'Layout overflowed at $label (${size.width}x${size.height})');
}

void main() {
  // 320x568 is the smallest screen still in real use (iPhone SE 1st gen and a
  // large slice of budget Android). If a layout survives this it survives most.
  const smallPhone = Size(320, 568);
  const normalPhone = Size(390, 844);

  group('RideStatusStrip', () {
    testWidgets('taxi: distance + duration + fare, small phone', (tester) async {
      await expectNoOverflow(
        tester,
        const RideStatusStrip(
          phase: 'To pickup',
          metrics: [
            RideStatusMetric(Icons.route, '12.4 km'),
            RideStatusMetric(Icons.schedule, '28 min'),
            RideStatusMetric(Icons.payments_outlined, 'Rs 340'),
          ],
        ),
        size: smallPhone,
        label: 'taxi strip',
      );
    });

    testWidgets('rental in overrun: metrics + accruing pill, small phone', (tester) async {
      await expectNoOverflow(
        tester,
        const RideStatusStrip(
          phase: 'Extra time',
          overrun: true,
          accruing: 2450,
          metrics: [
            RideStatusMetric(Icons.timer_outlined, '11h 45m / 4h', warn: true),
            RideStatusMetric(Icons.route, '287.6 / 60 km', warn: true),
          ],
        ),
        size: smallPhone,
        label: 'rental overrun strip',
      );
    });

    testWidgets('delivery: long sender name and item type, small phone', (tester) async {
      // Real user data is not tidy — this is the shape that breaks Rows.
      await expectNoOverflow(
        tester,
        const RideStatusStrip(
          phase: 'To receiver',
          accruing: 12500,
          accruingLabel: 'to collect',
          metrics: [
            RideStatusMetric(Icons.inventory_2_outlined, 'Refrigerated pharmaceutical consignment'),
            RideStatusMetric(Icons.person_pin_circle, 'Venkataraman Subramanian Iyer'),
          ],
        ),
        size: smallPhone,
        label: 'delivery strip with long names',
      );
    });

    testWidgets('hire overtime, normal phone', (tester) async {
      await expectNoOverflow(
        tester,
        const RideStatusStrip(
          phase: 'Overtime',
          overrun: true,
          accruing: 800,
          accruingLabel: 'overtime',
          metrics: [
            RideStatusMetric(Icons.timer_outlined, '9h 12m / 4h', warn: true),
            RideStatusMetric(Icons.trending_up, '+6h', warn: true),
          ],
        ),
        size: normalPhone,
        label: 'hire overtime strip',
      );
    });

    testWidgets('worst case: longest real phase + large COD + long metrics', (tester) async {
      // 'Returning to sender' is the longest phase lib/ride-phase.ts can emit,
      // and a five-figure COD is the widest realistic pill. Both at once, on the
      // narrowest screen, is the case that actually broke this widget.
      await expectNoOverflow(
        tester,
        const RideStatusStrip(
          phase: 'Returning to sender',
          accruing: 99999,
          accruingLabel: 'to collect',
          metrics: [
            RideStatusMetric(Icons.inventory_2_outlined, 'Temperature controlled goods'),
            RideStatusMetric(Icons.person_pin_circle, 'Chandrashekhar Balasubramanian'),
          ],
        ),
        size: smallPhone,
        label: 'worst case strip',
      );
    });

    testWidgets('degenerate: no metrics, no accruing', (tester) async {
      await expectNoOverflow(
        tester,
        const RideStatusStrip(phase: 'On trip', metrics: []),
        size: smallPhone,
        label: 'empty strip',
      );
    });
  });
}
