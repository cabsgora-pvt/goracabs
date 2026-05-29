import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../mock/mock_data.dart';
import '../../../models/models.dart';

abstract class RideEvent extends Equatable {
  @override List<Object?> get props => [];
}
class LoadRideRequestEvent extends RideEvent {}
class AcceptRideEvent extends RideEvent { final String id; AcceptRideEvent(this.id); @override List<Object?> get props => [id]; }
class RejectRideEvent extends RideEvent { final String id; RejectRideEvent(this.id); @override List<Object?> get props => [id]; }
class ArrivedEvent extends RideEvent {}
class StartRideEvent extends RideEvent {}
class EndRideEvent extends RideEvent {}

abstract class RideState extends Equatable {
  @override List<Object?> get props => [];
}
class RideInitial extends RideState {}
class RideLoading extends RideState {}
class IncomingRideState extends RideState {
  final RideRequestModel ride;
  IncomingRideState(this.ride);
  @override List<Object?> get props => [ride];
}
class RideAcceptedState extends RideState {
  final RideRequestModel ride;
  RideAcceptedState(this.ride);
  @override List<Object?> get props => [ride];
}
class ArrivedAtPickupState extends RideState {
  final RideRequestModel ride;
  ArrivedAtPickupState(this.ride);
  @override List<Object?> get props => [ride];
}
class RideStartedState extends RideState {
  final RideRequestModel ride;
  RideStartedState(this.ride);
  @override List<Object?> get props => [ride];
}
class RideEndedState extends RideState {
  final RideRequestModel ride;
  RideEndedState(this.ride);
  @override List<Object?> get props => [ride];
}
class RideRejectedState extends RideState {}

class RideBloc extends Bloc<RideEvent, RideState> {
  RideRequestModel? currentRide;

  RideBloc() : super(RideInitial()) {
    on<LoadRideRequestEvent>(_onLoad);
    on<AcceptRideEvent>(_onAccept);
    on<RejectRideEvent>(_onReject);
    on<ArrivedEvent>(_onArrived);
    on<StartRideEvent>(_onStart);
    on<EndRideEvent>(_onEnd);
  }

  Future<void> _onLoad(LoadRideRequestEvent e, Emitter emit) async {
    emit(RideLoading());
    final ride = await MockRideService.getIncomingRide();
    currentRide = ride;
    emit(IncomingRideState(ride));
  }

  Future<void> _onAccept(AcceptRideEvent e, Emitter emit) async {
    emit(RideLoading());
    await MockRideService.acceptRide(e.id);
    emit(RideAcceptedState(currentRide!));
  }

  Future<void> _onReject(RejectRideEvent e, Emitter emit) async {
    await MockRideService.rejectRide(e.id);
    emit(RideRejectedState());
  }

  Future<void> _onArrived(ArrivedEvent e, Emitter emit) async {
    await MockRideService.arrivedAtPickup(currentRide!.id);
    emit(ArrivedAtPickupState(currentRide!));
  }

  Future<void> _onStart(StartRideEvent e, Emitter emit) async {
    await MockRideService.startRide(currentRide!.id);
    emit(RideStartedState(currentRide!));
  }

  Future<void> _onEnd(EndRideEvent e, Emitter emit) async {
    await MockRideService.endRide(currentRide!.id);
    emit(RideEndedState(currentRide!));
  }
}
