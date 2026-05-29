import 'package:flutter_test/flutter_test.dart';
import 'package:customer_app/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const GoraCabsApp());

    // Verify that the app title or a key widget exists
    expect(find.text('Where to?'), findsOneWidget);
    expect(find.text('Choose a ride'), findsOneWidget);
  });
}
