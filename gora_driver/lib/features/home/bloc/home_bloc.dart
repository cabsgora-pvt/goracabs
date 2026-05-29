import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
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
    final d = await MockAuthService.getProfile();
    final s = await MockEarningsService.getSummary();
    driver = d;
    summary = s;
    emit(HomeLoaded(d, s));
  }

  Future<void> _onToggle(ToggleOnlineEvent e, Emitter emit) async {
    isOnline = e.isOnline;
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
