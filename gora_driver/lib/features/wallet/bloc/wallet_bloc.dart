import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../models/models.dart';
import '../../../services/driver_api_service.dart';

abstract class WalletEvent extends Equatable {
  @override List<Object?> get props => [];
}
class LoadWalletEvent extends WalletEvent {}

abstract class WalletState extends Equatable {
  @override List<Object?> get props => [];
}
class WalletInitial extends WalletState {}
class WalletLoading extends WalletState {}
class WalletLoaded extends WalletState {
  final double balance;
  final List<WalletTransaction> transactions;
  WalletLoaded(this.balance, this.transactions);
  @override List<Object?> get props => [balance, transactions];
}
class WalletBloc extends Bloc<WalletEvent, WalletState> {
  WalletBloc() : super(WalletInitial()) {
    on<LoadWalletEvent>(_onLoad);
  }
  Future<void> _onLoad(LoadWalletEvent e, Emitter emit) async {
    emit(WalletLoading());
    try {
      final res = await DriverApiService.getWallet();
      final balance = (res['balance'] as num?)?.toDouble() ?? 0;
      final txns = ((res['transactions'] as List?) ?? []).map((raw) {
        final t = Map<String, dynamic>.from(raw as Map);
        final amt = (t['amount'] as num?) ?? 0;
        final credit = amt >= 0;
        return WalletTransaction(
          id: t['_id']?.toString() ?? '',
          type: _prettyType(t['type']?.toString() ?? ''),
          description: (t['description'] ?? '').toString(),
          amount: '${credit ? '+' : '-'}₹${amt.abs().toStringAsFixed(0)}',
          date: _fmtDate(t['createdAt']?.toString()),
          isCredit: credit,
        );
      }).toList();
      emit(WalletLoaded(balance, txns));
    } catch (_) {
      emit(WalletLoaded(0, []));
    }
  }

  String _prettyType(String t) {
    switch (t) {
      case 'ride_earning': return 'Ride Earning';
      case 'commission': return 'Commission';
      case 'recharge': return 'Money Added';
      case 'withdrawal': return 'Withdrawal';
      case 'subscription': return 'Subscription';
      default: return t.isEmpty ? 'Transaction' : t;
    }
  }

  String _fmtDate(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final h = d.hour == 0 ? 12 : (d.hour > 12 ? d.hour - 12 : d.hour);
    return '${d.day} ${m[d.month - 1]}, $h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
  }
}
