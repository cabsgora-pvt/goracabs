import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'driver_api_service.dart';

// ── Layer 1: Foreground service ──────────────────────────────────────────────
// Keeps the driver receiving ride requests while the app is minimized. While
// online we run an Android foreground service (the persistent "You're online"
// notification, like Ola/Rapido). A background isolate polls for pending
// requests and, when one arrives, raises a full-screen "Incoming ride" alert
// that opens the app on tap.
//
// (Fully-killed delivery needs FCM push — see fcm_service notes. This layer
// covers the app being minimized / backgrounded.)

const _incomingChannelId = 'incoming_ride';

class RideAlertService {
  // Configure the foreground service + notification channels. Call once at startup.
  static Future<void> init() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'ride_online_service',
        channelName: 'Online Status',
        channelDescription: 'Shown while you are online and available for rides',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false, playSound: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(4000), // poll every 4s
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  // Start the service when the driver goes online.
  static Future<void> start() async {
    // Ask for notification permission (Android 13+) so alerts can show.
    final perm = await FlutterForegroundTask.checkNotificationPermission();
    if (perm != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    if (await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: "You're online",
      notificationText: 'Waiting for ride requests…',
      callback: startCallback,
    );
  }

  // Stop the service when the driver goes offline.
  static Future<void> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }
}

// Entry point for the background isolate that runs the polling task.
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(_RideAlertTaskHandler());
}

class _RideAlertTaskHandler extends TaskHandler {
  final _fln = FlutterLocalNotificationsPlugin();
  String _lastNotifiedId = '';

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Init the local-notifications plugin inside this isolate + create the
    // high-importance channel used for the full-screen ride alert.
    await _fln.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ));
    await _fln
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _incomingChannelId,
          'Incoming Ride Requests',
          description: 'Alerts when a new ride request arrives',
          importance: Importance.max,
          playSound: true,
        ));
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _poll();
  }

  Future<void> _poll() async {
    try {
      final res = await DriverApiService.getPendingRequests();
      final rides = (res['rides'] as List?) ?? [];
      if (rides.isEmpty) {
        _lastNotifiedId = '';
        FlutterForegroundTask.updateService(
          notificationTitle: "You're online",
          notificationText: 'Waiting for ride requests…',
        );
        return;
      }
      final first = Map<String, dynamic>.from(rides.first as Map);
      final id = first['id']?.toString() ?? '';
      if (id.isEmpty || id == _lastNotifiedId) return;
      _lastNotifiedId = id;

      final fare = '₹${first['totalFare'] ?? first['fare'] ?? ''}';
      final pickup = (first['pickupAddress'] ?? '').toString();
      final drop = (first['dropAddress'] ?? '').toString();

      await _showIncoming(fare, pickup, drop);
      FlutterForegroundTask.updateService(
        notificationTitle: 'New ride request!',
        notificationText: '$fare — tap to open',
      );
    } catch (_) {/* keep the service alive on transient errors */}
  }

  Future<void> _showIncoming(String fare, String pickup, String drop) async {
    await _fln.show(
      1001,
      'New Ride Request  $fare',
      pickup.isEmpty ? 'Tap to view and accept' : '$pickup → $drop',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _incomingChannelId,
          'Incoming Ride Requests',
          channelDescription: 'Alerts when a new ride request arrives',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call, // ring-style, shows over lock screen
          fullScreenIntent: true,
          autoCancel: true,
          ongoing: false,
        ),
      ),
    );
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  // Tapping the persistent "online" notification brings the app forward; the
  // in-app poller then opens the incoming-request screen.
  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }
}
