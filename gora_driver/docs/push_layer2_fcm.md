# Layer 2 — FCM push for ride requests when the app is fully closed

Layer 1 (foreground service, in `lib/services/ride_alert_service.dart`) already
covers the app being **minimized**. This adds **FCM push** so a ride request can
wake the app even when it's been **swiped away / killed**.

You must do the Firebase setup yourself (it needs an account + project). Once
`google-services.json` is in place, apply the steps below — they're written to
reuse the existing `incoming_ride` notification channel so the alert looks the
same as Layer 1.

---

## Step 1 — Create the Firebase project (one-time)

```bash
# in the gora_driver folder
dart pub global activate flutterfire_cli
flutterfire configure       # pick/create the Firebase project, select Android
```

This drops `android/app/google-services.json` and `lib/firebase_options.dart`.
Without `google-services.json` the Android build fails — so only do steps 2+
after this succeeds.

## Step 2 — Add packages

```yaml
# pubspec.yaml  (under dependencies)
  firebase_core: ^3.6.0
  firebase_messaging: ^15.1.3
```
```bash
flutter pub get
```

The `com.google.gms.google-services` Gradle plugin: add to
`android/settings.gradle.kts` plugins block:
```kotlin
id("com.google.gms.google-services") version "4.4.2" apply false
```
and apply it in `android/app/build.gradle.kts` plugins block:
```kotlin
id("com.google.gms.google-services")
```

## Step 3 — Create `lib/services/fcm_service.dart`

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../firebase_options.dart';
import 'driver_api_service.dart';

// Reuse the same channel Layer 1 uses so the alert is identical.
const _incomingChannelId = 'incoming_ride';

final _fln = FlutterLocalNotificationsPlugin();

// MUST be a top-level function.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _showIncoming(message);
}

Future<void> _showIncoming(RemoteMessage m) async {
  final d = m.data;
  final fare = d['fare'] ?? '';
  final pickup = d['pickupAddress'] ?? '';
  final drop = d['dropAddress'] ?? '';
  await _fln.show(
    1001,
    'New Ride Request  $fare',
    pickup.isEmpty ? 'Tap to view and accept' : '$pickup → $drop',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        _incomingChannelId, 'Incoming Ride Requests',
        importance: Importance.max, priority: Priority.max,
        category: AndroidNotificationCategory.call,
        fullScreenIntent: true, autoCancel: true,
      ),
    ),
  );
}

class FcmService {
  static Future<void> init() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await _fln.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ));
    await _fln
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _incomingChannelId, 'Incoming Ride Requests',
          importance: Importance.max, playSound: true,
        ));
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
    await FirebaseMessaging.instance.requestPermission();
    FirebaseMessaging.onMessage.listen(_showIncoming); // foreground
  }

  // Call AFTER login (once you have the driver JWT) so the token is stored.
  static Future<void> registerToken() async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await DriverApiService.saveFcmToken(token); // endpoint already exists
    }
    FirebaseMessaging.instance.onTokenRefresh.listen(DriverApiService.saveFcmToken);
  }
}
```

## Step 4 — Wire it in `main.dart`

```dart
// after WidgetsFlutterBinding.ensureInitialized();
await FcmService.init();
```
And after a successful login (in the OTP/auth success path):
```dart
await FcmService.registerToken();
```

`DriverApiService.saveFcmToken()` and the backend route
`POST /auth/driver/fcm-token` are **already in place** — nothing to add there.

## Step 5 — Send the push from the backend (on ride assignment)

Wherever a ride is created/offered to a driver, send a **data** message to that
driver's `fcmToken` (the field already exists on the Driver model). Example with
`firebase-admin` (needs a service-account key from the Firebase console):

```ts
import admin from 'firebase-admin'
// admin.initializeApp({ credential: admin.credential.cert(serviceAccount) })

await admin.messaging().send({
  token: driver.fcmToken,
  data: {
    type: 'ride_request',
    fare: `₹${ride.totalFare}`,
    pickupAddress: ride.pickupAddress,
    dropAddress: ride.dropAddress,
  },
  android: { priority: 'high' },
})
```

Use a **data-only** message (not `notification`) so `firebaseBackgroundHandler`
always runs and shows our full-screen alert, even when the app is killed.

---

## Notes / gotchas

- **Android 13+**: notification permission is requested in `FcmService.init()`.
- **Android 14+**: full-screen intents are restricted for non-call apps; the
  alert still shows as a high-priority heads-up. For a true over-lock-screen
  popup you may need to request the special "full-screen intent" access.
- **OEM battery savers** (Xiaomi/Vivo/Oppo/Realme) can delay/kill background
  delivery — advise drivers to allow autostart + disable battery optimization
  for the app (Layer 1 already calls `requestNotificationPermission`; you can
  also call `FlutterForegroundTask.requestIgnoreBatteryOptimization()`).
