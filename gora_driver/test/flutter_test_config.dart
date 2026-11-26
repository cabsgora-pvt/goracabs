import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gora_driver/services/token_store.dart';

/// Runs before every test file.
///
/// The session token lives in flutter_secure_storage (TokenStore). Widget tests
/// have no platform plugin, and an unanswered platform call never completes in
/// testWidgets' fake time — every screen that reads the token would hang. So
/// each test starts with an empty in-memory secure store on the plugin's
/// method channel. A test that installs its own handler on that channel
/// replaces this one; tests that seed a token through SharedPreferences still
/// work (TokenStore migrates it).
const _secureChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    final store = <String, String>{};
    TokenStore.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_secureChannel, (c) async {
      final args = (c.arguments as Map?) ?? const {};
      final key = args['key'] as String?;
      switch (c.method) {
        case 'read':
          return store[key];
        case 'write':
          if (key != null) store[key] = args['value'] as String;
          return null;
        case 'delete':
          store.remove(key);
          return null;
        case 'containsKey':
          return store.containsKey(key);
        case 'readAll':
          return Map<String, String>.from(store);
        case 'deleteAll':
          store.clear();
          return null;
      }
      return null;
    });
  });
  await testMain();
}
