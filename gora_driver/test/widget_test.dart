import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gora_driver/app/app.dart';

// Smoke test: the driver app builds and mounts a MaterialApp.
//
// This file previously held the unmodified Flutter counter template — it
// referenced a `MyApp` class that has never existed in this project, so the
// suite did not compile at all.
//
// GoraDriverApp supplies its own providers and bloc, so it can be pumped
// directly. Assertions run on the first frame — pumpAndSettle would never
// return, because the splash screen polls.
void main() {
  testWidgets('Driver app boots without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(const GoraDriverApp());

    expect(find.byType(GoraDriverApp), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);

    // The splash schedules a 2s Future.delayed before routing. The test binding
    // asserts no timer outlives the widget tree, so drain it rather than leave
    // it pending — otherwise this passes locally and fails as a timer leak.
    await tester.pump(const Duration(seconds: 3));
  });
}
