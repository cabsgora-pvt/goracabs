import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../models/models.dart';
import '../../../services/driver_api_service.dart';
import '../../../services/location_service.dart';
import '../../../services/ride_alert_service.dart';

abstract class HomeEvent extends Equatable {
  @override List<Object?> get props => [];
}
class ToggleOnlineEvent extends HomeEvent {
  final bool isOnline;
  ToggleOnlineEvent(this.isOnline);
  @override List<Object?> get props => [isOnline];
}
class LoadHomeDataEvent extends HomeEvent {}

abstract class HomeState extends Equatable {
  @override List<Object?> get props => [];
}
class HomeInitial extends HomeState {}
class HomeLoading extends HomeState {}
class HomeLoaded extends HomeState {
  final DriverModel driver;
  final Map<String, String> summary;
  HomeLoaded(this.driver, this.summary);
  @override List<Object?> get props => [driver, summary];
}
class OnlineStatusChanged extends HomeState {
  final bool isOnline;
  /// Set when going online moved the driver to another zone (zone auto-follow).
  final String? zoneChangedTo;
  OnlineStatusChanged(this.isOnline, {this.zoneChangedTo});
  @override List<Object?> get props => [isOnline, zoneChangedTo];
}
// The server refused to put this driver online: the account is on hold
// (wrong face scan, wallet mis-transaction, held by admin …).
class AccountHoldState extends HomeState {
  final String message;
  final String kind;
  /// Bumped per refusal, so tapping GO again shows the dialog again.
  final int seq;
  AccountHoldState(this.message, {this.kind = 'manual', this.seq = 0});
  @override List<Object?> get props => [message, kind, seq];
}
// Going online did not happen — the server refused or could not be reached,
// or the online service (which needs location permission) would not start.
// The driver stays offline and is told why, instead of a toggle that says
// "online" while no request can arrive.
class GoOnlineFailedState extends HomeState {
  final String message;
  /// Bumped per failure, so the same reason shows again on the next try.
  final int seq;
  GoOnlineFailedState(this.message, {this.seq = 0});
  @override List<Object?> get props => [message, seq];
}

/// Why going online failed, for the driver.
const goOnlineNoNetworkText = 'Could not reach Gora, so you are still offline. Check your internet and try again.';
const goOnlineNoServiceText =
    'You are still offline: ride alerts need location access. Allow location (and notifications) for Gora Captain, then go online again.';

/// The line for a server refusal of going online.
String goOnlineRefusedText(Map<String, dynamic> res) {
  final e = (res['error'] ?? '').toString().trim();
  return e.isEmpty ? 'Could not go online. Please try again.' : 'Could not go online: $e';
}

// A mid-ride face check came back mismatched/unanswered on a previous ride —
// the server refused to let this driver go online again until they re-verify.
class FaceVerificationLockedState extends HomeState {
  final String reason;
  FaceVerificationLockedState(this.reason);
  @override List<Object?> get props => [reason];
}

class HomeBloc extends Bloc<HomeEvent, HomeState> {
  bool isOnline = false;
  DriverModel? driver;
  Map<String, String> summary = {};
  int _holdSeq = 0;
  int _failSeq = 0;

  /// Starts the online service. A phone with no such plugin (a test, a
  /// non-Android build) has nothing to start, which is not a failure; the
  /// plugin saying it could not start is.
  static Future<bool> _startService() async {
    try {
      return await RideAlertService.start();
    } on MissingPluginException {
      return true;
    } catch (_) {
      return false;
    }
  }

  HomeBloc() : super(HomeInitial()) {
    on<LoadHomeDataEvent>(_onLoad);
    on<ToggleOnlineEvent>(_onToggle);
  }

  Future<void> _onLoad(LoadHomeDataEvent e, Emitter emit) async {
    emit(HomeLoading());
    // Restore the driver's online status (survives the home screen being rebuilt
    // after a ride — it must NOT auto-go-offline; only manual toggle changes it).
    try {
      final prefs = await SharedPreferences.getInstance();
      isOnline = prefs.getBool('driver_online') ?? false;
    } catch (_) {}
    DriverModel d;
    try {
      final res = await DriverApiService.getProfile();
      final data = res['driver'] as Map<String, dynamic>?;
      d = data != null ? DriverModel.fromApi(data) : (driver ?? DriverModel.fromApi(const {}));
    } catch (_) {
      // Keep whatever was last loaded rather than wiping the driver's own
      // name/photo/wallet off the home screen on a transient network blip.
      d = driver ?? DriverModel.fromApi(const {});
    }
    driver = d;
    // Real earnings summary (today / week / rides / distance)
    Map<String, String> s;
    try {
      final r = await DriverApiService.getEarningsSummary();
      s = {
        'today': '₹ ${r['today'] ?? 0}',
        'week': '₹${r['week'] ?? 0}',
        'totalRides': '${r['totalRides'] ?? 0}',
        'totalDistance': '${r['todayDistance'] ?? 0} km',
      };
    } catch (_) {
      s = {'today': '₹ 0', 'week': '₹0', 'totalRides': '0', 'totalDistance': '0 km'};
    }
    summary = s;
    emit(HomeLoaded(d, s));
    // Reopened while online (the app had been killed): the background service
    // died with it and the server may have timed the driver out. Nothing used
    // to restart either, so the toggle said "online" while no request could
    // arrive once the app was minimised.
    if (isOnline) await _restoreOnline(emit);
  }

  Future<void> _restoreOnline(Emitter emit) async {
    try {
      final pos = await LocationService.getCurrentLocation();
      final res = await DriverApiService.setOnline(true, pos?.latitude, pos?.longitude);
      if (res['accountHold'] == true || res['faceVerificationRequired'] == true) {
        // Refused now: show it, and stop claiming to be online.
        await _goOfflineLocally();
        if (res['accountHold'] == true) {
          final msg = (res['error'] ?? '').toString();
          emit(AccountHoldState(
            msg.isNotEmpty ? msg : 'Your account is on hold. Please contact support.',
            kind: (res['holdKind'] ?? 'manual').toString(),
            seq: ++_holdSeq,
          ));
        } else {
          emit(FaceVerificationLockedState((res['faceVerificationReason'] ?? 'mismatch').toString()));
        }
        return;
      }
    } catch (_) {/* network blip: the service still polls, and the next toggle re-posts */}
    if (!await _startService()) {
      // No alerts could arrive: say so instead of showing "online".
      await _goOfflineLocally();
      try { await DriverApiService.setOnline(false); } catch (_) {}
      emit(GoOnlineFailedState(RideAlertService.lastStartFailure ?? goOnlineNoServiceText, seq: ++_failSeq));
    }
  }

  Future<void> _goOfflineLocally() async {
    isOnline = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('driver_online', false);
    } catch (_) {}
    try { await RideAlertService.stop(); } catch (_) {}
  }

  Future<void> _onToggle(ToggleOnlineEvent e, Emitter emit) async {
    // Going online specifically can be refused server-side (face verification
    // lock) — check that BEFORE touching local state or the foreground
    // service, so a refusal doesn't leave the UI showing "online" anyway.
    String? zoneChangedTo;
    if (e.isOnline) {
      try {
        // No fix yet → send none. A made-up point (this used to be Ahmedabad)
        // put the driver in another city for dispatch until the first ping.
        final pos = await LocationService.getCurrentLocation();
        final res = await DriverApiService.setOnline(true, pos?.latitude, pos?.longitude);
        if (res['accountHold'] == true) {
          final msg = (res['error'] ?? '').toString();
          emit(AccountHoldState(
            msg.isNotEmpty ? msg : 'Your account is on hold. Please contact support.',
            kind: (res['holdKind'] ?? 'manual').toString(),
            seq: ++_holdSeq,
          ));
          return;
        }
        if (res['faceVerificationRequired'] == true) {
          emit(FaceVerificationLockedState((res['faceVerificationReason'] ?? 'mismatch').toString()));
          return;
        }
        if (res['error'] != null) {
          // Refused, or no answer (an HTML error page, a 5xx): still offline.
          emit(GoOnlineFailedState(goOnlineRefusedText(res), seq: ++_failSeq));
          return;
        }
        final z = (res['zoneChangedTo'] ?? '').toString();
        if (z.isNotEmpty) zoneChangedTo = z;
      } catch (_) {
        // Timed out / no connection: the server never put us online.
        emit(GoOnlineFailedState(goOnlineNoNetworkText, seq: ++_failSeq));
        return;
      }
      // The online service is what delivers requests while minimised, and it
      // cannot run without location permission: no service, no "online".
      if (!await _startService()) {
        try { await DriverApiService.setOnline(false); } catch (_) {}
        await _goOfflineLocally();
        emit(GoOnlineFailedState(RideAlertService.lastStartFailure ?? goOnlineNoServiceText, seq: ++_failSeq));
        return;
      }
    } else {
      try { await DriverApiService.setOnline(false); } catch (_) {}
    }

    isOnline = e.isOnline;
    // Persist so it survives navigation/app restarts
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('driver_online', e.isOnline);
    } catch (_) {}
    // Stop the foreground service when going offline (going online started it
    // above, before anything said "online").
    if (!e.isOnline) {
      try { await RideAlertService.stop(); } catch (_) {}
    }
    emit(OnlineStatusChanged(e.isOnline, zoneChangedTo: zoneChangedTo));
  }
}
