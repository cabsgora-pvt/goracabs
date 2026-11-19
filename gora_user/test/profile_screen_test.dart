import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:customer_app/providers/theme_provider.dart';
import 'package:customer_app/providers/user_provider.dart';
import 'package:customer_app/screens/profile_screen.dart';
import 'package:customer_app/theme/app_theme.dart';

// The profile page through a mocked server: what it shows, and what Save sends.
Map<String, dynamic> user = {};
final saves = <Map<String, dynamic>>[];
bool failSave = false;

MockClient get client => MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/auth/user/profile')) {
        return http.Response(jsonEncode({'user': user}), 200);
      }
      if (p.endsWith('/auth/user/register')) {
        final b = jsonDecode(req.body) as Map<String, dynamic>;
        saves.add(b);
        if (failSave) return http.Response(jsonEncode({'error': 'nope'}), 500);
        user = {...user, ...b};
        return http.Response(jsonEncode({'success': true, 'user': user}), 200);
      }
      return http.Response('{}', 200);
    });

Future<void> act(Future<void> Function() body) => http.runWithClient(body, () => client);

Widget app({ThemeMode mode = ThemeMode.light}) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: mode,
        home: const ProfileScreen(),
      ),
    );

Future<void> open(WidgetTester tester, {Size size = const Size(400, 860), ThemeMode mode = ThemeMode.light}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await act(() async {
    await tester.pumpWidget(app(mode: mode));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  });
}

void main() {
  setUp(() {
    user = {'name': 'Rahul Mehta', 'phone': '9876543210', 'email': '', 'city': 'Rajkot', 'idNumber': ''};
    saves.clear();
    failSave = false;
    SharedPreferences.setMockInitialValues({'user_token': 't'});
  });

  testWidgets('shows the loaded profile; empty details read "Not added"', (tester) async {
    await open(tester);
    expect(find.text('Rahul Mehta'), findsNWidgets(2)); // header + details row
    expect(find.text('+91 9876543210'), findsNWidgets(2));
    expect(find.text('Verified'), findsOneWidget);
    expect(find.text('Not added'), findsNWidgets(2)); // email, ID number
    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.text('Save changes'), findsNothing);
  });

  testWidgets('edit → save sends the new details and returns to the view', (tester) async {
    await open(tester);
    await act(() async {
      await tester.tap(find.text('Edit profile'));
      await tester.pump();
      expect(find.text('Save changes'), findsOneWidget);
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(4)); // name, email, city, ID — phone is locked
      await tester.enterText(fields.at(0), 'Rahul K Mehta');
      await tester.enterText(fields.at(1), 'rahul@example.com');
      await tester.tap(find.text('Save changes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });
    expect(saves, hasLength(1));
    expect(saves.single['name'], 'Rahul K Mehta');
    expect(saves.single['email'], 'rahul@example.com');
    expect(saves.single['city'], 'Rajkot');
    expect(find.text('Save changes'), findsNothing);
    expect(find.text('rahul@example.com'), findsOneWidget);
    expect(find.text('Profile updated'), findsOneWidget);
  });

  testWidgets('a bad email is refused before anything is sent', (tester) async {
    await open(tester);
    await act(() async {
      await tester.tap(find.text('Edit profile'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(1), 'not-an-email');
      await tester.tap(find.text('Save changes'));
      await tester.pump();
    });
    expect(saves, isEmpty);
    expect(find.text('Please enter a valid email address'), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget); // still editing
  });

  testWidgets('a failed save keeps the rider\'s edits on screen', (tester) async {
    failSave = true;
    await open(tester);
    await act(() async {
      await tester.tap(find.text('Edit profile'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(0), 'Typed Name');
      await tester.tap(find.text('Save changes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });
    expect(find.text('Save changes'), findsOneWidget);
    expect(find.text('Typed Name'), findsOneWidget);
    expect(find.textContaining('Failed to update'), findsOneWidget);
  });

  testWidgets('Save stays reachable above an open keyboard', (tester) async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);
    await open(tester);
    await act(() async {
      await tester.tap(find.text('Edit profile'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(2), 'Ahmedabad');
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      final save = tester.getRect(find.text('Save changes'));
      expect(save.bottom, lessThanOrEqualTo(860 - 320));
      await tester.tap(find.text('Save changes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });
    expect(saves.single['city'], 'Ahmedabad');
  });

  testWidgets('Cancel drops the edits', (tester) async {
    await open(tester);
    await act(() async {
      await tester.tap(find.text('Edit profile'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(0), 'Something Else');
      await tester.tap(find.text('Cancel'));
      await tester.pump();
    });
    expect(saves, isEmpty);
    expect(find.text('Rahul Mehta'), findsNWidgets(2));
    expect(find.text('Something Else'), findsNothing);
  });

  for (final size in const [Size(320, 640), Size(400, 860)]) {
    for (final mode in const [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('no overflow at ${size.width.toInt()}x${size.height.toInt()} ${mode.name}', (tester) async {
        user = {...user, 'name': 'A Very Long Rider Name That Keeps Going On', 'email': 'a.really.long.email.address@example.com'};
        await open(tester, size: size, mode: mode);
        expect(tester.takeException(), isNull);
        await act(() async {
          await tester.tap(find.text('Edit profile'));
          await tester.pump();
        });
        expect(tester.takeException(), isNull);
      });
    }
  }
}
