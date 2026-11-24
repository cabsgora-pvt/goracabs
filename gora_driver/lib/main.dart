import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'app/app.dart';
import 'services/ride_alert_service.dart';
import 'services/session.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  // Foreground-service setup so ride requests keep coming while minimized.
  FlutterForegroundTask.initCommunicationPort();
  RideAlertService.init();
  // A 401 anywhere — here or in the background service — ends the session.
  Session.install();
  FlutterForegroundTask.addTaskDataCallback((data) {
    if (data == unauthorizedMessage) Session.expired();
  });
  runApp(const GoraDriverApp());
}
