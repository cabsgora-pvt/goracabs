import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../models/models.dart';
import '../../../services/driver_api_service.dart';

abstract class HistoryEvent extends Equatable {
  @override List<Object?> get props => [];
}
class LoadHistoryEvent extends HistoryEvent {}

abstract class HistoryState extends Equatable {
  @override List<Object?> get props => [];
}
class HistoryInitial extends HistoryState {}
class HistoryLoading extends HistoryState {}
class HistoryLoaded extends HistoryState {
  final List<TripModel> trips;
  // Set when the list below is empty because the request failed, not because
  // the driver genuinely has no trips — history_page.dart uses this to show
  // "couldn't load" instead of a misleading empty state.
  final bool loadFailed;
  HistoryLoaded(this.trips, {this.loadFailed = false});
  @override List<Object?> get props => [trips, loadFailed];
}

class HistoryBloc extends Bloc<HistoryEvent, HistoryState> {
  HistoryBloc() : super(HistoryInitial()) {
    on<LoadHistoryEvent>(_onLoad);
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
          userProfilePicUrl: (r['riderProfilePicUrl'] ?? '').toString(),
          service: (r['service'] ?? 'taxi').toString(),
          vehicleType: (r['vehicleType'] ?? '').toString(),
          tripType: (r['tripType'] ?? 'one_way').toString(),
          cityFrom: (r['cityFrom'] ?? '').toString(),
          cityTo: (r['cityTo'] ?? '').toString(),
          numPassengers: (r['numPassengers'] as num?)?.toInt() ?? 0,
        );
      }).toList();
      emit(HistoryLoaded(trips));
    } catch (_) {
      // A real driver's trip list on a network error — showing realistic-looking
      // fake trips here would read as real ride history, not a loading failure.
      emit(HistoryLoaded(const [], loadFailed: true));
    }
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
