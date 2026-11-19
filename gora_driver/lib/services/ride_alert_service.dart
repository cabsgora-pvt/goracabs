import 'package:flutter/widgets.dart';
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
const _fgBeat = 'app-foreground';

class RideAlertService {
  /// The id of the full-screen "New Ride Request" heads-up. One fixed id, so
  /// a newer request replaces it and it can be cancelled from either isolate.
  static const incomingNotificationId = 1001;

  /// Takes the "New Ride Request ₹…" heads-up off the screen and puts the
  /// online notification back to its waiting text. Called once a request has
  /// been dealt with — accepted, declined, timed out, or gone from the feed —
  /// so the alert no longer sits over the app for minutes (it was swallowing
  /// Back presses). Display only: dispatch and polling are untouched.
  static Future<void> clearIncomingAlert() async {
    try {
      await FlutterLocalNotificationsPlugin().cancel(incomingNotificationId);
    } catch (_) {}
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
          notificationTitle: "You're online",
          notificationText: 'Waiting for ride requests…',
        );
      }
    } catch (_) {}
  }

  /// Sent by the in-app poller on each of its polls while the app is on
  /// screen. The background task then skips its own poll: both used to hit
  /// /rides/driver/pending every 4 s while the driver was looking at the app.
  /// Only sent while resumed, so once the app is minimised the heartbeats stop
  /// and the background poll is back within [foregroundWindow].
  static void foregroundHeartbeat() {
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
    try { FlutterForegroundTask.sendDataToTask(_fgBeat); } catch (_) {}
  }

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

/// How long one heartbeat from the on-screen app holds off the background
/// poll. A bit over the app's own 4 s poll, so one late heartbeat does not
/// double up.
const foregroundWindow = Duration(seconds: 6);

/// True while the last heartbeat from the on-screen app is recent enough for
/// the background task to leave polling to it.
bool appOnScreen(DateTime? lastBeat, DateTime now) =>
    lastBeat != null && now.difference(lastBeat) < foregroundWindow;

class _RideAlertTaskHandler extends TaskHandler {
  final _fln = FlutterLocalNotificationsPlugin();
  String _lastNotifiedId = '';
  DateTime? _appSeenAt;

  @override
  void onReceiveData(Object data) {
    if (data == _fgBeat) _appSeenAt = DateTime.now();
  }

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
    if (appOnScreen(_appSeenAt, DateTime.now())) return;
    _poll();
  }

  Future<void> _poll() async {
    try {
      final res = await DriverApiService.getPendingRequests();
      final rides = (res['rides'] as List?) ?? [];
      // The request this alert was for is no longer pending (taken, accepted,
      // cancelled): take its heads-up down.
      if (_lastNotifiedId.isNotEmpty &&
          !rides.any((r) => r is Map && r['id']?.toString() == _lastNotifiedId)) {
        await _fln.cancel(RideAlertService.incomingNotificationId);
      }
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
      RideAlertService.incomingNotificationId,
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
