import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gora_driver/features/ride/widgets/otp_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// The OTP dialog used to start a trip and to hand over a parcel. Both versions
// disposed their text controller the moment the dialog closed, while the field
// was still animating out; any such error fails these tests.
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  Future<Future<String?>> open(WidgetTester tester) async {
    late Future<String?> result;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(
        onPressed: () => result = OtpDialog.show(context,
            title: 'Enter Delivery OTP', label: 'OTP from Receiver', hint: 'e.g. 4821', action: 'Deliver'),
        child: const Text('open'),
      ),
    ))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('returns what was typed, and closes cleanly', (tester) async {
    final result = await open(tester);
    expect(find.text('Enter Delivery OTP'), findsOneWidget);
    expect(find.text('OTP from Receiver'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '7390');
    await tester.tap(find.text('Deliver'));
    await tester.pumpAndSettle();
    expect(await result, '7390');
    expect(find.text('Enter Delivery OTP'), findsNothing);
  });

  testWidgets('Cancel returns nothing', (tester) async {
    final result = await open(tester);
    await tester.enterText(find.byType(TextField), '7390');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await result, isNull);
  });

  testWidgets('nothing typed returns an empty code, not null', (tester) async {
    final result = await open(tester);
    await tester.tap(find.text('Deliver'));
    await tester.pumpAndSettle();
    expect(await result, '');
  });
}
