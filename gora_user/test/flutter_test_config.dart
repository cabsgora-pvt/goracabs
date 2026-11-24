import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:customer_app/services/session_guard.dart';

/// Runs around every test file in this directory.
///
/// The rider's token lives in flutter_secure_storage. There is no keystore
/// under flutter_tester, and a call to the missing plugin only fails on the
/// real event loop — which a widget test's fake clock never reaches, so every
/// API call would wait forever for its token. The plugin's own in-memory mock
/// stands in, emptied before each test so no token leaks from one to the next
/// (tests still seed SharedPreferences, which getToken migrates from).
/// The once-only 401 sign-out is re-armed for each test as well.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    // A 401 in one test must not leave the next one "already signed out".
    SessionGuard.reset();
  });
  await testMain();
}
