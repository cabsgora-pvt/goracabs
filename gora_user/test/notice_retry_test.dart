import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:customer_app/widgets/ride_ui/service_form.dart';

// Parcel "Failed to load" and rental "Failed to load packages" had no way to
// try again short of picking the address again.
void main() {
  testWidgets('a notice with onRetry offers Retry and runs it', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: NoticeRow('Failed to load', tone: NoticeTone.warning, onRetry: () => calls++))));
    await tester.tap(find.text('Retry'));
    expect(calls, 1);
  });

  testWidgets('a plain notice has no Retry', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: NoticeRow('No vehicles here'))));
    expect(find.text('Retry'), findsNothing);
  });
}
