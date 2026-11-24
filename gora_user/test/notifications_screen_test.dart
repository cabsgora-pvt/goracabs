import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:customer_app/providers/theme_provider.dart';
import 'package:customer_app/providers/user_provider.dart';
import 'package:customer_app/screens/home_screen.dart';
import 'package:customer_app/screens/notifications_screen.dart';
import 'package:customer_app/theme/app_theme.dart';

// The rider's notification feed from /auth/user/notifications: newest first,
// admin images (relative /uploads paths made absolute), empty state, refresh.

List<Map<String, dynamic>> feed = [];
int fetches = 0;
bool fail = false;

MockClient get client => MockClient((req) async {
      if (req.url.path.endsWith('/auth/user/notifications')) {
        fetches++;
        expect(req.headers['Authorization'], 'Bearer t');
        if (fail) return http.Response(jsonEncode({'error': 'Unauthorized'}), 401);
        return http.Response(jsonEncode({'notifications': feed}), 200);
      }
      return http.Response('{}', 200);
    });

Future<void> act(Future<void> Function() body) => http.runWithClient(body, () => client);

Widget app(Widget home) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp(theme: AppTheme.lightTheme, home: home),
    );

Future<void> open(WidgetTester tester, {Widget home = const NotificationsScreen()}) async {
  tester.view.physicalSize = const Size(400, 860);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await act(() async {
    await tester.pumpWidget(app(home));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  });
}

String ago(Duration d) => DateTime.now().toUtc().subtract(d).toIso8601String();

void main() {
  setUp(() {
    fetches = 0;
    fail = false;
    feed = [];
    SharedPreferences.setMockInitialValues({'user_token': 't'});
  });

  testWidgets('lists notifications newest first with title, body and time', (tester) async {
    feed = [
      {'id': 'a', 'title': 'Older one', 'body': 'Sent yesterday', 'imageUrl': '', 'sentAt': ago(const Duration(hours: 30)), 'type': 'broadcast'},
      {'id': 'b', 'title': 'Diwali offer', 'body': '20% off all rides', 'imageUrl': '', 'sentAt': ago(const Duration(minutes: 5)), 'type': 'broadcast'},
      {'id': 'c', 'title': 'For you', 'body': 'Your refund is done', 'imageUrl': '', 'sentAt': ago(const Duration(hours: 3)), 'type': 'personal'},
    ];
    await open(tester);
    expect(find.text('Notifications'), findsOneWidget);
    final yDiwali = tester.getTopLeft(find.text('Diwali offer')).dy;
    final yForYou = tester.getTopLeft(find.text('For you')).dy;
    final yOlder = tester.getTopLeft(find.text('Older one')).dy;
    expect(yDiwali < yForYou && yForYou < yOlder, isTrue, reason: 'newest first');
    expect(find.text('20% off all rides'), findsOneWidget);
    expect(find.text('5 min ago'), findsOneWidget);
    expect(find.text('3 h ago'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget, reason: 'personal message icon');
    expect(find.byType(Image), findsNothing, reason: 'no imageUrl → no image');
  });

  testWidgets('images: relative /uploads made absolute, https kept; a broken one leaves nothing', (tester) async {
    feed = [
      {'id': 'a', 'title': 'Relative', 'body': '', 'imageUrl': '/uploads/promo.jpg', 'sentAt': ago(const Duration(minutes: 1)), 'type': 'broadcast'},
      {'id': 'b', 'title': 'Absolute', 'body': '', 'imageUrl': 'https://cdn.example.com/x.png', 'sentAt': ago(const Duration(minutes: 2)), 'type': 'broadcast'},
    ];
    await open(tester);
    final urls = tester.widgetList<Image>(find.byType(Image)).map((i) => (i.image as NetworkImage).url).toList();
    expect(urls, ['https://goracabs.com/uploads/promo.jpg', 'https://cdn.example.com/x.png']);
    // The test binding answers every image request with an error; the image
    // and its frame must disappear rather than show a broken glyph.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    expect(find.byType(ClipRRect), findsNothing);
    expect(find.byIcon(Icons.broken_image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty feed shows the empty state; pull to refresh fetches again', (tester) async {
    await open(tester);
    expect(find.text('No notifications yet'), findsOneWidget);
    expect(fetches, 1);
    feed = [
      {'id': 'n', 'title': 'Fresh news', 'body': 'Hello', 'imageUrl': '', 'sentAt': ago(const Duration(minutes: 2)), 'type': 'broadcast'},
    ];
    await act(() async {
      await tester.fling(find.text('No notifications yet'), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
    });
    expect(fetches, 2);
    expect(find.text('Fresh news'), findsOneWidget);
    expect(find.text('No notifications yet'), findsNothing);
  });

  testWidgets('a failed load says so and offers Retry', (tester) async {
    fail = true;
    await open(tester);
    expect(find.text('Unauthorized'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    fail = false;
    await act(() async {
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
    });
    expect(find.text('No notifications yet'), findsOneWidget);
  });

  testWidgets('home menu has a Notifications entry that opens the feed', (tester) async {
    SharedPreferences.setMockInitialValues({'token': 't', 'user_token': 't'});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/geolocator'), (call) async => null);
    await open(tester, home: const HomeScreen());
    await act(() async {
      await tester.tap(find.byTooltip('Menu'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    });
    expect(find.widgetWithText(ListTile, 'Notifications'), findsOneWidget);
    await act(() async {
      await tester.tap(find.widgetWithText(ListTile, 'Notifications'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    });
    expect(find.byType(NotificationsScreen), findsOneWidget);
    expect(fetches, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 9));
    while (tester.takeException() != null) {}
  });
}
