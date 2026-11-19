import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gora_driver/features/account/pages/profile_page.dart';
import 'package:gora_driver/features/ride/pages/invoice_page.dart';
import 'package:gora_driver/models/models.dart';
import 'package:gora_driver/features/wallet/pages/wallet_page.dart';
import 'package:gora_driver/features/wallet/widgets/add_balance_sheet.dart';
import 'package:gora_driver/providers/driver_provider.dart';

// Wallet "Add balance" and the driver's photo, which is the face scan from
// registration and cannot be changed.
bool gatewayOn = true;
final requests = <http.Request>[];

MockClient get client => MockClient((req) async {
      requests.add(req);
      final p = req.url.path;
      if (p.endsWith('/auth/driver/wallet/recharge')) {
        return http.Response(jsonEncode({'enabled': gatewayOn, 'min': 50, 'max': 20000, 'presets': [200, 500, 1000, 2000]}), 200);
      }
      if (p.endsWith('/auth/driver/wallet')) {
        return http.Response(jsonEncode({'balance': 120, 'transactions': []}), 200);
      }
      if (p.endsWith('/auth/driver/profile')) {
        return http.Response(jsonEncode({'driver': {
          'name': 'Suresh Patel', 'phone': '9876543210', 'profilePicUrl': '/uploads/face-scan.jpg',
          'faceReferencePhotoUrl': '/uploads/face-scan.jpg', 'rating': 4.8, 'totalRides': 12,
        }}), 200);
      }
      return http.Response('{}', 200);
    });

Future<void> act(Future<void> Function() body) => http.runWithClient(body, () => client);

Future<void> settle(WidgetTester tester, [int ms = 600]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    gatewayOn = true;
    requests.clear();
    SharedPreferences.setMockInitialValues({'driver_token': 't'});
  });

  void phone(WidgetTester tester, [Size size = const Size(400, 860)]) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('wallet', () {
    Widget app() => ChangeNotifierProvider(create: (_) => DriverProvider(), child: const MaterialApp(home: WalletPage()));

    testWidgets('shows Add balance next to Withdraw', (tester) async {
      phone(tester);
      await act(() async {
        await tester.pumpWidget(app());
        await settle(tester);
      });
      expect(find.text('Add balance'), findsOneWidget);
      expect(find.text('Withdraw'), findsOneWidget);
      expect(find.text('₹ 120.00'), findsOneWidget);
    });

    testWidgets('Add balance opens the sheet with quick amounts', (tester) async {
      phone(tester);
      await act(() async {
        await tester.pumpWidget(app());
        await settle(tester);
        await tester.tap(find.text('Add balance'));
        await settle(tester);
      });
      for (final p in ['₹200', '₹500', '₹1000', '₹2000']) {
        expect(find.text(p), findsOneWidget);
      }
      await act(() async {
        await tester.tap(find.text('₹500'));
        await tester.pump();
      });
      expect(find.text('Add ₹500'), findsOneWidget);
      expect(find.textContaining('not available yet'), findsNothing);
    });

    testWidgets('gateway off: the sheet says so and cannot pay', (tester) async {
      gatewayOn = false;
      phone(tester);
      await act(() async {
        await tester.pumpWidget(app());
        await settle(tester);
        await tester.tap(find.text('Add balance'));
        await settle(tester);
      });
      expect(find.textContaining('Online recharge is not available yet'), findsOneWidget);
      final btn = find.ancestor(of: find.text('Add balance').last, matching: find.byType(ElevatedButton));
      if (btn.evaluate().isNotEmpty) {
        expect(tester.widget<ElevatedButton>(btn.first).onPressed, isNull);
      }
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
    });
  });

  group('add balance sheet', () {
    Future<double?> open(WidgetTester tester, Future<Map<String, dynamic>> Function(int) pay) async {
      phone(tester);
      double? result;
      var closed = false;
      await act(() async {
        await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
          body: Center(child: ElevatedButton(
            onPressed: () async {
              result = await showModalBottomSheet<double>(context: context, isScrollControlled: true,
                  builder: (_) => AddBalanceSheet(payOverride: pay));
              closed = true;
            },
            child: const Text('open'),
          )),
        ))));
        await tester.tap(find.text('open'));
        await settle(tester);
      });
      addTearDown(() => closed);
      return result;
    }

    testWidgets('below the minimum is refused before paying', (tester) async {
      var paid = 0;
      await open(tester, (a) async { paid++; return {'success': true, 'walletBalance': 100.0}; });
      await act(() async {
        await tester.enterText(find.byKey(const ValueKey('add_balance_amount')), '20');
        await tester.pump();
        await tester.tap(find.text('Add ₹20'));
        await settle(tester, 200);
      });
      expect(find.text('Minimum is ₹50'), findsOneWidget);
      expect(paid, 0);
    });

    testWidgets('above the maximum is refused', (tester) async {
      var paid = 0;
      await open(tester, (a) async { paid++; return {'success': true}; });
      await act(() async {
        await tester.enterText(find.byKey(const ValueKey('add_balance_amount')), '25000');
        await tester.pump();
        await tester.tap(find.text('Add ₹25000'));
        await settle(tester, 200);
      });
      expect(find.text('Maximum is ₹20000'), findsOneWidget);
      expect(paid, 0);
    });

    testWidgets('a successful payment closes the sheet with the new balance', (tester) async {
      int? paidAmount;
      phone(tester);
      double? result;
      await act(() async {
        await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
          body: Center(child: ElevatedButton(
            onPressed: () async {
              result = await showModalBottomSheet<double>(context: context, isScrollControlled: true,
                  builder: (_) => AddBalanceSheet(payOverride: (a) async {
                    paidAmount = a;
                    return {'success': true, 'walletBalance': 620.0, 'amount': 500};
                  }));
            },
            child: const Text('open'),
          )),
        ))));
        await tester.tap(find.text('open'));
        await settle(tester);
        await tester.tap(find.text('₹500'));
        await tester.pump();
        await tester.tap(find.text('Add ₹500'));
        await settle(tester);
      });
      expect(paidAmount, 500);
      expect(result, 620.0);
      expect(find.byType(AddBalanceSheet), findsNothing);
    });

    testWidgets('a failed payment stays open and says why', (tester) async {
      await open(tester, (a) async => {'error': 'Payment cancelled'});
      await act(() async {
        await tester.tap(find.text('₹1000'));
        await tester.pump();
        await tester.tap(find.text('Add ₹1000'));
        await settle(tester);
      });
      expect(find.text('Payment cancelled'), findsOneWidget);
      expect(find.byType(AddBalanceSheet), findsOneWidget);
    });

    for (final size in const [Size(320, 640), Size(400, 860)]) {
      testWidgets('no overflow at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        phone(tester, size);
        await act(() async {
          await tester.pumpWidget(ChangeNotifierProvider(create: (_) => DriverProvider(), child: const MaterialApp(home: WalletPage())));
          await settle(tester);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Add balance'));
          await settle(tester);
        });
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('profile photo', () {
    testWidgets('shows the face-scan photo with no way to change it', (tester) async {
      phone(tester);
      final picks = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/image_picker'), (c) async { picks.add(c); return null; });
      final dp = DriverProvider();
      await act(() async {
        await tester.pumpWidget(ChangeNotifierProvider.value(value: dp, child: const MaterialApp(home: ProfilePage())));
        await settle(tester);
      });
      expect(dp.profilePicUrl, endsWith('/uploads/face-scan.jpg'));
      expect(find.text('Face verified photo'), findsOneWidget);
      expect(find.byIcon(Icons.camera_alt), findsNothing);
      expect(find.textContaining('cannot be changed'), findsOneWidget);
      await act(() async {
        await tester.tap(find.byKey(const ValueKey('driver_profile_photo')), warnIfMissed: false);
        await settle(tester);
      });
      expect(picks, isEmpty, reason: 'tapping the photo must not open the gallery');
      expect(requests.where((r) => r.url.path.endsWith('/profile-pic')), isEmpty);
      while (tester.takeException() != null) {}
    });
  });

  group('order complete', () {
    for (final commission in const [18, 0]) {
      testWidgets('shows the earning, never the commission (commission $commission)', (tester) async {
        phone(tester);
        final ride = RideRequestModel.fromJson({
          'id': 'r1', 'service': 'taxi', 'riderName': 'Rahul', 'vehicleType': 'Cab',
          'pickupAddress': 'A', 'dropAddress': 'B', 'pickupLat': 22.29, 'pickupLng': 70.79,
          'dropLat': 22.30, 'dropLng': 70.80, 'fare': 90, 'totalFare': 110, 'distance': 4.35,
          'paymentMode': 'cash', 'status': 'completed',
        });
        await act(() async {
          await tester.pumpWidget(MaterialApp(
            onGenerateRoute: (_) => MaterialPageRoute(
              settings: RouteSettings(arguments: RideCompletionArgs(ride, driverEarning: 92, adminProfit: commission)),
              builder: (_) => const InvoicePage(),
            ),
          ));
          await settle(tester, 300);
        });
        expect(find.text('Order Complete'), findsOneWidget);
        expect(find.text('₹92'), findsOneWidget);
        expect(find.textContaining('Commission'), findsNothing);
        expect(find.textContaining('COMMISSION'), findsNothing);
        expect(find.text('- ₹18'), findsNothing);
        expect(find.text('Rate your Customer'), findsOneWidget);
      });
    }
  });
}
