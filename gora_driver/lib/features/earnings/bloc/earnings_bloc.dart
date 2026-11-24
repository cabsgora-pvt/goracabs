import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../services/driver_api_service.dart';

// Aggregated earnings for one period (a day, or a month, or "today").
class PeriodStat extends Equatable {
  final String label;    // "Mon" / "Jul" / "Today"
  final String sub;      // "12" (date) / "2026" (year) / "6 Jul"
  final double amount;
  final int rides;
  final double distanceKm;
  final int durationMin;
  final bool isCurrent;  // the current day / month → highlighted
  const PeriodStat({
    required this.label,
    required this.sub,
    this.amount = 0,
    this.rides = 0,
    this.distanceKm = 0,
    this.durationMin = 0,
    this.isCurrent = false,
  });
  @override
  List<Object?> get props => [label, sub, amount, rides, distanceKm, durationMin, isCurrent];
}

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
  final PeriodStat today;
  final List<PeriodStat> weekly;   // last 7 days
  final List<PeriodStat> monthly;  // 12 months of the current year
  EarningsLoaded({required this.today, required this.weekly, required this.monthly});
  @override List<Object?> get props => [today, weekly, monthly];
}

typedef _Ride = ({DateTime date, double amount, double distanceKm, int durationMin});

class EarningsBloc extends Bloc<EarningsEvent, EarningsState> {
  /// At most this many history pages (50 trips each) are read for the charts.
  static const maxHistoryPages = 20;

  static const _dow = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  EarningsBloc() : super(EarningsInitial()) {
    on<LoadEarningsEvent>(_onLoad);
  }

  Future<void> _onLoad(LoadEarningsEvent e, Emitter emit) async {
    emit(EarningsLoading());
    final rides = <_Ride>[];
    final now0 = DateTime.now();
    // The charts cover this year (months) and the last 7 days (which can reach
    // back into last year). History comes 50 trips a page, newest first: read
    // pages until they reach back past that, or run out. One page used to be
    // all there was, so a busy driver's earlier months showed ₹0.
    final since = DateTime(now0.year, 1, 1).isBefore(now0.subtract(const Duration(days: 7)))
        ? DateTime(now0.year, 1, 1)
        : now0.subtract(const Duration(days: 7));
    final raws = <Map<String, dynamic>>[];
    try {
      for (var page = 1; page <= maxHistoryPages; page++) {
        final res = await DriverApiService.getTripHistory(page: page);
        if (res['error'] != null) break;
        final list = ((res['rides'] as List?) ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        raws.addAll(list);
        if (res['hasMore'] != true || list.isEmpty) break;
        final oldest = DateTime.tryParse(list.last['createdAt']?.toString() ?? '')?.toLocal();
        if (oldest != null && oldest.isBefore(since)) break;
      }
    } catch (_) {}
    try {
      for (final r in raws) {
        final status = (r['status'] ?? '').toString();
        if (status.isNotEmpty && status != 'completed') continue; // earnings = completed rides only
        final d = DateTime.tryParse(r['createdAt']?.toString() ?? '')?.toLocal();
        if (d == null) continue;
        rides.add((
          date: d,
          amount: ((r['driverEarning'] ?? r['totalFare'] ?? r['fare'] ?? 0) as num).toDouble(),
          distanceKm: ((r['distance'] ?? 0) as num).toDouble(),
          durationMin: ((r['duration'] ?? 0) as num).toInt(),
        ));
      }
    } catch (_) {}

    final now = DateTime.now();
    bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

    final today = _agg('Today', '${now.day} ${_mon[now.month - 1]}',
        rides.where((r) => sameDay(r.date, now)), current: true);

    final weekly = <PeriodStat>[];
    for (int i = 6; i >= 0; i--) {
      final day = now.subtract(Duration(days: i));
      weekly.add(_agg(_dow[day.weekday - 1], '${day.day}',
          rides.where((r) => sameDay(r.date, day)), current: sameDay(day, now)));
    }

    final monthly = <PeriodStat>[];
    // Up to the current month only: a future month has no earnings to show.
    for (int m = 1; m <= now.month; m++) {
      monthly.add(_agg(_mon[m - 1], '${now.year}',
          rides.where((r) => r.date.year == now.year && r.date.month == m), current: m == now.month));
    }

    emit(EarningsLoaded(today: today, weekly: weekly, monthly: monthly));
  }

  PeriodStat _agg(String label, String sub, Iterable<_Ride> rides, {bool current = false}) {
    double amount = 0, distanceKm = 0;
    int durationMin = 0, count = 0;
    for (final r in rides) {
      amount += r.amount;
      distanceKm += r.distanceKm;
      durationMin += r.durationMin;
      count++;
    }
    return PeriodStat(
      label: label, sub: sub, amount: amount, rides: count,
      distanceKm: distanceKm, durationMin: durationMin, isCurrent: current,
    );
  }
}
