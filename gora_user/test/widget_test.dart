import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:customer_app/main.dart';
import 'package:customer_app/providers/user_provider.dart';
import 'package:customer_app/providers/theme_provider.dart';

// Smoke test: the app builds and mounts a MaterialApp.
//
// GoraCabsApp reads ThemeProvider via context.watch, so the providers from
// main() have to be supplied here too — pumping the widget bare throws.
//
// Deliberately pump a single frame rather than pumpAndSettle: the splash screen
// starts timers and network calls, and settling would wait on them forever.
void main() {
  testWidgets('App boots without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => UserProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ],
        child: const GoraCabsApp(),
      ),
    );

    expect(find.byType(GoraCabsApp), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
