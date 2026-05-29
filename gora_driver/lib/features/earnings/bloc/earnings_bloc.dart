import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../mock/mock_data.dart';
import '../../../models/models.dart';

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
    final s = await MockEarningsService.getSummary();
    emit(EarningsLoaded(w, s));
  }
}
