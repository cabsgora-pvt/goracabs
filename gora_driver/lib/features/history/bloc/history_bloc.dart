import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../models/models.dart';
import '../../../services/driver_api_service.dart';
import '../../../utils/format_minutes.dart';

abstract class HistoryEvent extends Equatable {
  @override List<Object?> get props => [];
}
class LoadHistoryEvent extends HistoryEvent {}
/// The next page of older trips (the history is served 50 at a time).
class LoadMoreHistoryEvent extends HistoryEvent {}

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
  /// The server has older trips than these.
  final bool hasMore;
  /// The next page is on its way.
  final bool loadingMore;
  /// Loading the next page failed; it can be retried.
  final bool moreFailed;
  HistoryLoaded(this.trips, {this.loadFailed = false, this.hasMore = false, this.loadingMore = false, this.moreFailed = false});
  @override List<Object?> get props => [trips, loadFailed, hasMore, loadingMore, moreFailed];
}

class HistoryBloc extends Bloc<HistoryEvent, HistoryState> {
  HistoryBloc() : super(HistoryInitial()) {
    on<LoadHistoryEvent>(_onLoad);
    on<LoadMoreHistoryEvent>(_onMore);
  }

  int _page = 0;
  final List<TripModel> _trips = [];

  Future<void> _onLoad(LoadHistoryEvent e, Emitter emit) async {
    emit(HistoryLoading());
    try {
      final res = await DriverApiService.getTripHistory(page: 1);
      if (res['error'] != null) throw Exception(res['error']);
      _page = 1;
      _trips..clear()..addAll(_parse(res));
      emit(HistoryLoaded(List.of(_trips), hasMore: res['hasMore'] == true));
    } catch (_) {
      // A real driver's trip list on a network error — showing realistic-looking
      // fake trips here would read as real ride history, not a loading failure.
      emit(HistoryLoaded(const [], loadFailed: true));
    }
  }

  Future<void> _onMore(LoadMoreHistoryEvent e, Emitter emit) async {
    final cur = state;
    if (cur is! HistoryLoaded || !cur.hasMore || cur.loadingMore) return;
    emit(HistoryLoaded(cur.trips, hasMore: true, loadingMore: true));
    try {
      final res = await DriverApiService.getTripHistory(page: _page + 1);
      if (res['error'] != null) throw Exception(res['error']);
      _page++;
      // A trip that moved up a page between the two calls is not shown twice.
      final seen = _trips.map((t) => t.id).toSet();
      _trips.addAll(_parse(res).where((t) => t.id.isEmpty || seen.add(t.id)));
      emit(HistoryLoaded(List.of(_trips), hasMore: res['hasMore'] == true));
    } catch (_) {
      emit(HistoryLoaded(cur.trips, hasMore: true, moreFailed: true));
    }
  }

  List<TripModel> _parse(Map<String, dynamic> res) {
      final rides = (res['rides'] as List?) ?? [];
      return rides.map<TripModel>((raw) {
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
          duration: formatMinutes(((r['duration'] ?? 0) as num).round()),
          rating: ((r['riderRating'] ?? 0) as num).toDouble(),
          userProfilePicUrl: (r['riderProfilePicUrl'] ?? '').toString(),
          service: (r['service'] ?? 'taxi').toString(),
          vehicleType: (r['vehicleType'] ?? '').toString(),
          tripType: (r['tripType'] ?? 'one_way').toString(),
          cityFrom: (r['cityFrom'] ?? '').toString(),
          cityTo: (r['cityTo'] ?? '').toString(),
          numPassengers: (r['numPassengers'] as num?)?.toInt() ?? 0,
          driverEarning: (r['driverEarning'] as num?) ?? 0,
          commission: (r['commissionAmount'] as num?) ?? 0,
        );
      }).toList();
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
