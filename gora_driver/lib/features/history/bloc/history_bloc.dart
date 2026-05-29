import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../mock/mock_data.dart';
import '../../../models/models.dart';

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
    final trips = await MockHistoryService.getHistory();
    emit(HistoryLoaded(trips));
  }
  Future<void> _onDetail(LoadTripDetailEvent e, Emitter emit) async {
    emit(HistoryLoading());
    final trip = await MockHistoryService.getTripDetail(e.id);
    emit(TripDetailLoaded(trip));
  }
}
