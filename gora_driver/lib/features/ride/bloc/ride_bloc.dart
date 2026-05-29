import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../mock/mock_data.dart';
import '../../../models/models.dart';
import '../../../services/driver_api_service.dart';

abstract class RideEvent extends Equatable {
  @override List<Object?> get props => [];
}
class LoadRideRequestEvent extends RideEvent {}
// Seeds the bloc with a real ride request (from home polling)
class SetRideRequestEvent extends RideEvent { final RideRequestModel ride; SetRideRequestEvent(this.ride); @override List<Object?> get props => [ride]; }
class AcceptRideEvent extends RideEvent { final String id; AcceptRideEvent(this.id); @override List<Object?> get props => [id]; }
class RejectRideEvent extends RideEvent { final String id; RejectRideEvent(this.id); @override List<Object?> get props => [id]; }
class ArrivedEvent extends RideEvent {}
class StartRideEvent extends RideEvent { final String otp; StartRideEvent([this.otp = '']); @override List<Object?> get props => [otp]; }
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
  final num adminProfit;
  final num driverEarning;
  RideEndedState(this.ride, {this.adminProfit = 0, this.driverEarning = 0});
  @override List<Object?> get props => [ride, adminProfit, driverEarning];
}
class RideRejectedState extends RideState {}
// Another driver already took the ride (HTTP 409)
class RideTakenState extends RideState {}
// OTP entered by driver did not match
class OtpErrorState extends RideState {
  final RideRequestModel ride;
  OtpErrorState(this.ride);
  @override List<Object?> get props => [ride];
}

class RideBloc extends Bloc<RideEvent, RideState> {
  RideRequestModel? currentRide;

  RideBloc() : super(RideInitial()) {
    on<LoadRideRequestEvent>(_onLoad);
    on<SetRideRequestEvent>(_onSet);
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

  void _onSet(SetRideRequestEvent e, Emitter emit) {
    currentRide = e.ride;
    emit(IncomingRideState(e.ride));
  }

  Future<void> _onAccept(AcceptRideEvent e, Emitter emit) async {
    emit(RideLoading());
    try {
      final res = await DriverApiService.acceptRide(e.id);
      final status = res['_status'] as int? ?? 200;
      if (status == 409) { emit(RideTakenState()); return; }
      if (res['success'] == true) { emit(RideAcceptedState(currentRide!)); return; }
      emit(RideTakenState());
    } catch (_) {
      emit(RideTakenState());
    }
  }

  Future<void> _onReject(RejectRideEvent e, Emitter emit) async {
    try { await DriverApiService.rejectRide(e.id); } catch (_) {}
    emit(RideRejectedState());
  }

  Future<void> _onArrived(ArrivedEvent e, Emitter emit) async {
    try { await DriverApiService.arrivedRide(currentRide!.id); } catch (_) {}
    emit(ArrivedAtPickupState(currentRide!));
  }

  Future<void> _onStart(StartRideEvent e, Emitter emit) async {
    try {
      final res = await DriverApiService.startRide(currentRide!.id, e.otp);
      if (res['success'] == true) {
        emit(RideStartedState(currentRide!));
      } else {
        emit(OtpErrorState(currentRide!));
      }
    } catch (_) {
      emit(OtpErrorState(currentRide!));
    }
  }

  Future<void> _onEnd(EndRideEvent e, Emitter emit) async {
    emit(RideLoading());
    try {
      final res = await DriverApiService.completeRide(currentRide!.id);
      emit(RideEndedState(
        currentRide!,
        adminProfit: (res['adminProfit'] ?? 0) as num,
        driverEarning: (res['driverEarning'] ?? 0) as num,
      ));
    } catch (_) {
      emit(RideEndedState(currentRide!));
    }
  }
}
