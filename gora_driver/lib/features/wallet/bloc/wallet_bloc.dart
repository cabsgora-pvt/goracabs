import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../mock/mock_data.dart';
import '../../../models/models.dart';

abstract class WalletEvent extends Equatable {
  @override List<Object?> get props => [];
}
class LoadWalletEvent extends WalletEvent {}
class WithdrawEvent extends WalletEvent {
  final double amount;
  WithdrawEvent(this.amount);
  @override List<Object?> get props => [amount];
}

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
class WithdrawSuccess extends WalletState {}
class WalletError extends WalletState {
  final String msg;
  WalletError(this.msg);
}

class WalletBloc extends Bloc<WalletEvent, WalletState> {
  WalletBloc() : super(WalletInitial()) {
    on<LoadWalletEvent>(_onLoad);
    on<WithdrawEvent>(_onWithdraw);
  }
  Future<void> _onLoad(LoadWalletEvent e, Emitter emit) async {
    emit(WalletLoading());
    final b = await MockWalletService.getBalance();
    final t = await MockWalletService.getTransactions();
    emit(WalletLoaded(b, t));
  }
  Future<void> _onWithdraw(WithdrawEvent e, Emitter emit) async {
    emit(WalletLoading());
    await MockWalletService.withdraw(e.amount);
    emit(WithdrawSuccess());
  }
}
