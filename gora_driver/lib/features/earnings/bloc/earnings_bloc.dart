import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../services/driver_api_service.dart';

// Aggregated earnings for one period (a day, or a month, or "today").
class PeriodStat extends Equatable {
  final String label;    // "Mon" / "Jul" / "Today"
  final String sub;      // "12" (date) / "2026" (year) / "6 Jul"
  /// What the driver kept (driverEarning), all modes.
  final double amount;
  final int rides;
  final double distanceKm;
  final int durationMin;
  final bool isCurrent;  // the current day / month → highlighted
  /// Of [amount]: earned on cash rides, and on online / wallet rides.
  final double cash;
  final double online;
  /// Gora's commission on these trips, and the riders' tips.
  final double commission;
  final double tips;
  const PeriodStat({
    required this.label,
    required this.sub,
    this.amount = 0,
    this.rides = 0,
    this.distanceKm = 0,
    this.durationMin = 0,
    this.isCurrent = false,
    this.cash = 0,
    this.online = 0,
    this.commission = 0,
    this.tips = 0,
  });
  @override
  List<Object?> get props => [label, sub, amount, rides, distanceKm, durationMin, isCurrent, cash, online, commission, tips];
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
  final List<PeriodStat> monthly;  // the current year, up to this month
  /// Incentive rewards reached in the current day / week / month
  /// (GET /auth/driver/incentives), by period.
  final Map<String, double> incentives;
  EarningsLoaded({required this.today, required this.weekly, required this.monthly, this.incentives = const {}});
  @override List<Object?> get props => [today, weekly, monthly, incentives];
}
/// The earnings could not be read. Not shown as ₹0: a driver who sees "₹0
/// today" after a day's work thinks the money is gone.
class EarningsError extends EarningsState {
  final String message;
  EarningsError(this.message);
  @override List<Object?> get props => [message];
}

const _dow = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}'.replaceAll(RegExp(r'[^0-9.\-]'), '')) ?? 0;
int _i(Object? v) => _d(v).round();

PeriodStat _stat(String label, String sub, Map? b, {bool current = false}) => PeriodStat(
  label: label, sub: sub, isCurrent: current,
  amount: _d(b?['earning']), rides: _i(b?['rides']),
  distanceKm: _d(b?['distanceKm']), durationMin: _i(b?['durationMin']),
  cash: _d(b?['cash']), online: _d(b?['online']),
  commission: _d(b?['commission']), tips: _d(b?['tips']),
);

/// The Earnings screen's figures from GET /rides/driver/earnings.
///
/// The server buckets completed trips by the IST day of completedAt
/// (`breakdown`: today, days[7], months[this year]). [now] is the phone's
/// day, used only for labels. An older server without `breakdown` gives its
/// 7-day `daily` amounts (no split) and no months.
EarningsLoaded earningsFrom(Map<String, dynamic> res, {Map<String, double> incentives = const {}, DateTime? now}) {
  final n = now ?? DateTime.now();
  final b = res['breakdown'];
  if (b is Map) {
    final days = ((b['days'] as List?) ?? const []).whereType<Map>().toList();
    final weekly = <PeriodStat>[];
    for (var i = 0; i < days.length; i++) {
      final date = DateTime.tryParse('${days[i]['date']}');
      final isLast = i == days.length - 1;
      weekly.add(_stat(date != null ? _dow[date.weekday - 1] : '', date != null ? '${date.day}' : '',
          days[i], current: isLast));
    }
    final months = ((b['months'] as List?) ?? const []).whereType<Map>().toList();
    final monthly = <PeriodStat>[
      for (var i = 0; i < months.length; i++)
        _stat(_mon[(_i(months[i]['month']) - 1).clamp(0, 11)], '${months[i]['year'] ?? n.year}', months[i],
            current: i == months.length - 1),
    ];
    final todayDate = days.isNotEmpty ? DateTime.tryParse('${days.last['date']}') : null;
    final t = todayDate ?? n;
    return EarningsLoaded(
      today: _stat('Today', '${t.day} ${_mon[t.month - 1]}', b['today'] as Map?, current: true),
      weekly: weekly,
      monthly: monthly,
      incentives: incentives,
    );
  }
  // Older server: amounts only.
  final daily = ((res['daily'] as List?) ?? const []).whereType<Map>().toList();
  final weekly = <PeriodStat>[];
  for (var i = 0; i < 7; i++) {
    final day = n.subtract(Duration(days: 6 - i));
    final row = i < daily.length ? daily[i] : null;
    weekly.add(PeriodStat(
      label: _dow[day.weekday - 1], sub: '${day.day}', isCurrent: i == 6,
      amount: _d(row?['amount']), rides: _i(row?['rides']), distanceKm: _d(row?['distance']),
    ));
  }
  final monthly = [
    for (var m = 1; m <= n.month; m++) PeriodStat(label: _mon[m - 1], sub: '${n.year}', isCurrent: m == n.month),
  ];
  final todayRow = weekly.last;
  return EarningsLoaded(
    today: PeriodStat(label: 'Today', sub: '${n.day} ${_mon[n.month - 1]}', isCurrent: true,
        amount: todayRow.amount, rides: todayRow.rides, distanceKm: todayRow.distanceKm),
    weekly: weekly,
    monthly: monthly,
    incentives: incentives,
  );
}

/// Incentive rewards reached so far, by period ('day' | 'week' | 'month').
Map<String, double> incentivesReached(Map<String, dynamic> res) {
  final out = <String, double>{};
  for (final r in ((res['incentives'] as List?) ?? const []).whereType<Map>()) {
    if (r['achieved'] != true) continue;
    final p = (r['period'] ?? 'day').toString();
    out[p] = (out[p] ?? 0) + _d(r['reward']);
  }
  return out;
}

class EarningsBloc extends Bloc<EarningsEvent, EarningsState> {
  EarningsBloc() : super(EarningsInitial()) {
    on<LoadEarningsEvent>(_onLoad);
  }

  Future<void> _onLoad(LoadEarningsEvent e, Emitter emit) async {
    emit(EarningsLoading());
    Map<String, dynamic> res;
    try {
      res = await DriverApiService.getEarnings();
    } catch (_) {
      emit(EarningsError('Could not load your earnings. Check your internet and try again.'));
      return;
    }
    if (res['error'] != null) {
      emit(EarningsError('Could not load your earnings: ${res['error']}'));
      return;
    }
    // Incentives are extra: when they cannot be read the earnings still show.
    var incentives = const <String, double>{};
    try {
      final inc = await DriverApiService.getIncentives();
      if (inc['error'] == null) incentives = incentivesReached(inc);
    } catch (_) {}
    emit(earningsFrom(res, incentives: incentives));
  }
}
