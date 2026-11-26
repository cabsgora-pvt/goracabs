import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:customer_app/services/api_service.dart';
import 'package:customer_app/services/app_foreground.dart';
import 'package:customer_app/services/session_guard.dart';
import 'package:customer_app/services/session_refresh.dart';
import 'package:customer_app/services/update_gate.dart';

/// Runs around every test file in this directory.
///
/// The rider's token lives in flutter_secure_storage. There is no keystore
/// under flutter_tester, and a call to the missing plugin only fails on the
/// real event loop — which a widget test's fake clock never reaches, so every
/// API call would wait forever for its token. The plugin's own in-memory mock
/// stands in, emptied before each test so no token leaks from one to the next
/// (tests still seed SharedPreferences, which getToken migrates from).
/// The once-only 401 sign-out is re-armed for each test as well.
///
/// The app's start / resume work (update check, session refresh, payment
/// retry) is off: tests that cover it call it directly. Cached configs, the
/// refresh hint and the update state are cleared so no test sees another's.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  AppForeground.enabled = false;
  setUp(() {
    ApiService.resetConfigCaches();
    SessionRefresher.reset();
    UpdateGate.reset();
    FlutterSecureStorage.setMockInitialValues({});
    // A 401 in one test must not leave the next one "already signed out".
    SessionGuard.reset();
  });
  await testMain();
}
