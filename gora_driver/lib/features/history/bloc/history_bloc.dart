import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../mock/mock_data.dart';
import '../../../models/models.dart';
import '../../../services/driver_api_service.dart';

abstract class HistoryEvent extends Equatable {
  @override List<Object?> get props => [];
}
class LoadHistoryEvent extends HistoryEvent {}
class LoadTripDetailEvent extends HistoryEvent {
  final String id;
  LoadTripDetailEvent(this.id);
  @override List<Object?> get props => [id];
}

abstract class HistoryState extends Equatable {
  @override List<Object?> get props => [];
}
class HistoryInitial extends HistoryState {}
class HistoryLoading extends HistoryState {}
class HistoryLoaded extends HistoryState {
  final List<TripModel> trips;
  HistoryLoaded(this.trips);
  @override List<Object?> get props => [trips];
}
class TripDetailLoaded extends HistoryState {
  final TripModel trip;
  TripDetailLoaded(this.trip);
  @override List<Object?> get props => [trip];
}

class HistoryBloc extends Bloc<HistoryEvent, HistoryState> {
  HistoryBloc() : super(HistoryInitial()) {
    on<LoadHistoryEvent>(_onLoad);
    on<LoadTripDetailEvent>(_onDetail);
  }
  Future<void> _onLoad(LoadHistoryEvent e, Emitter emit) async {
    emit(HistoryLoading());
    try {
      final res = await DriverApiService.getTripHistory();
      final rides = (res['rides'] as List?) ?? [];
      final trips = rides.map<TripModel>((raw) {
        final r = Map<String, dynamic>.from(raw as Map);
        final total = r['totalFare'] ?? r['fare'] ?? 0;
        return TripModel(
          id: r['_id']?.toString() ?? '',
          userName: (r['riderName'] ?? 'Rider').toString(),
          pickupAddress: (r['pickupAddress'] ?? '').toString(),
          dropAddress: (r['dropAddress'] ?? '').toString(),
          distance: '${r['distance'] ?? 0} km',
          fare: '₹ $total',
          date: _fmtDate(r['createdAt']?.toString()),
          status: (r['status'] ?? '').toString(),
          paymentMode: (r['paymentMode'] ?? 'cash').toString(),
          duration: '${r['duration'] ?? 0} min',
          rating: ((r['riderRating'] ?? 0) as num).toDouble(),
        );
      }).toList();
      emit(HistoryLoaded(trips));
    } catch (_) {
      final trips = await MockHistoryService.getHistory();
      emit(HistoryLoaded(trips));
    }
  }
  Future<void> _onDetail(LoadTripDetailEvent e, Emitter emit) async {
    emit(HistoryLoading());
    final trip = await MockHistoryService.getTripDetail(e.id);
    emit(TripDetailLoaded(trip));
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '';
    try {
      final d = DateTime.parse(iso).toLocal();
      return '${d.day}/${d.month}/${d.year}, ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}
