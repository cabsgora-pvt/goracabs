import 'package:flutter/widgets.dart';

/// The app's one RouteObserver (registered on MaterialApp.navigatorObservers).
///
/// Screens that poll (home, taxi booking) subscribe with RouteAware and stop
/// their timers in didPushNext - another screen now covers them - and start
/// them again in didPopNext, instead of polling the server for a map nobody
/// can see.
// PageRoute only: a bottom sheet or dialog over a screen does not pause it.
final RouteObserver<PageRoute<dynamic>> appRouteObserver = RouteObserver<PageRoute<dynamic>>();
