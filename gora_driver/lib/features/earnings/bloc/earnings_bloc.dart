import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../models/models.dart';
import '../../../services/driver_api_service.dart';

abstract class EarningsEvent extends Equatable {
  @override List<Object?> get props => [];
}
class LoadEarningsEvent extends EarningsEvent {
  final DateTime? date;
  LoadEarningsEvent({this.date});
  @override List<Object?> get props => [date];
}

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
    List<EarningsModel> weekly = [];
    Map<String, String> summary = {'today': '₹0', 'week': '₹0', 'month': '₹0', 'totalRides': '0'};
    try {
      final res = await DriverApiService.getEarnings(date: e.date);
      final daily = (res['daily'] as List?) ?? [];
      weekly = daily.map((raw) {
        final m = Map<String, dynamic>.from(raw as Map);
        return EarningsModel(
          date: (m['date'] ?? '').toString(),
          amount: (m['amount'] ?? '0').toString(),
          rides: (m['rides'] ?? '0').toString(),
          distance: (m['distance'] ?? '0 km').toString(),
          duration: (m['duration'] ?? '—').toString(),
        );
      }).toList();
      final s = (res['summary'] as Map?) ?? {};
      summary = s.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {}
    emit(EarningsLoaded(weekly, summary));
  }
}
