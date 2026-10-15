import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Reproduces the booking pattern used by the rental, hire, parcel and outstation
// screens, to establish whether it can create duplicate bookings.
//
// Each of those screens starts the booking from INSIDE a bottom sheet's builder:
//
//     showModalBottomSheet(builder: (ctx) {
//       () async { await _book(); _startPolling(); }();
//       return ...;
//     });
//
// A builder is not a one-time callback. This test counts how many times that
// "booking" runs when the sheet has to rebuild — here because the screen size
// changes, as it does when the phone rotates.

void main() {
  testWidgets('booking inside a sheet builder re-runs when the sheet rebuilds',
      (tester) async {
    var bookings = 0;

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showModalBottomSheet(
                context: context,
                isDismissible: false,
                enableDrag: false,
                isScrollControlled: true,
                builder: (ctx) {
                  // Same shape as the production code.
                  () async { bookings++; }();
                  return SizedBox(
                    height: MediaQuery.of(ctx).size.height,
                    child: const Center(child: Text('Finding your driver')),
                  );
                },
              ),
              child: const Text('Book'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Book'));
    await tester.pumpAndSettle();
    expect(bookings, greaterThanOrEqualTo(1));
    final afterOpen = bookings;

    // The phone rotates.
    tester.view.physicalSize = const Size(1920, 1080);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpAndSettle();

    // ignore: avoid_print
    print('bookings after opening the sheet: $afterOpen, after rotating: $bookings');
    expect(bookings, greaterThan(afterOpen),
        reason: 'If this fails, the builder did not re-run and the pattern is safe');
  });
}
