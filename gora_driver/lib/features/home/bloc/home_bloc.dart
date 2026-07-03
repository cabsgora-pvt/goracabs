import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../mock/mock_data.dart';
import '../../../models/models.dart';
import '../../../services/driver_api_service.dart';
import '../../../services/location_service.dart';

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
  OnlineStatusChanged(this.isOnline);
  @override List<Object?> get props => [isOnline];
}

class HomeBloc extends Bloc<HomeEvent, HomeState> {
  bool isOnline = false;
  DriverModel? driver;
  Map<String, String> summary = {};

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
    final d = await MockAuthService.getProfile();
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
  }

  Future<void> _onToggle(ToggleOnlineEvent e, Emitter emit) async {
    isOnline = e.isOnline;
    // Persist so it survives navigation/app restarts
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('driver_online', e.isOnline);
    } catch (_) {}
    // Report online/offline + current location to backend
    try {
      final pos = await LocationService.getCurrentLocation();
      final lat = pos?.latitude ?? 23.0225;
      final lng = pos?.longitude ?? 72.5714;
      await DriverApiService.setOnline(e.isOnline, lat, lng);
    } catch (_) {/* keep UI responsive even if network fails */}
    emit(OnlineStatusChanged(e.isOnline));
  }
}
