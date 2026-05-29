import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../mock/mock_data.dart';
import '../../../models/models.dart';
import '../../../services/driver_api_service.dart';

abstract class EarningsEvent extends Equatable {
  @override List<Object?> get props => [];
}
class LoadEarningsEvent extends EarningsEvent {}

abstract class EarningsState extends Equatable {
  @override List<Object?> get props => [];
}
class EarningsInitial extends EarningsState {}
class EarningsLoading extends EarningsState {}
class EarningsLoaded extends EarningsState {
  final List<EarningsModel> weekly;
  final Map<String, String> summary;
  EarningsLoaded(this.weekly, this.summary);
  @override List<Object?> get props => [weekly, summary];
}

class EarningsBloc extends Bloc<EarningsEvent, EarningsState> {
  EarningsBloc() : super(EarningsInitial()) {
    on<LoadEarningsEvent>(_onLoad);
  }
  Future<void> _onLoad(LoadEarningsEvent e, Emitter emit) async {
    emit(EarningsLoading());
    final w = await MockEarningsService.getWeeklyEarnings();
    final s = Map<String, String>.from(await MockEarningsService.getSummary());
    // Overlay real totals from driver profile (earnings already net of commission)
    try {
      final res = await DriverApiService.getProfile();
      final d = res['driver'] as Map?;
      if (d != null) {
        final totalEarnings = d['totalEarnings'] ?? 0;
        final totalRides = d['totalRides'] ?? 0;
        s['month'] = '₹ $totalEarnings';
        s['totalRides'] = '$totalRides';
      }
    } catch (_) {}
    emit(EarningsLoaded(w, s));
  }
}
