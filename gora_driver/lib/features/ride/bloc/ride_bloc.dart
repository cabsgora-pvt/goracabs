import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../models/models.dart';
import '../../../services/driver_api_service.dart';

// RideBloc is created per-ride with `currentRide` already set (see
// on_ride_page.dart) — there is no "load the incoming request" event here;
// incoming_requests_page.dart fetches and accepts the ride directly via
// DriverApiService before this bloc is ever created.
abstract class RideEvent extends Equatable {
  @override List<Object?> get props => [];
}
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
class RideAcceptedState extends RideState {
  final RideRequestModel ride;
  RideAcceptedState(this.ride);
  @override List<Object?> get props => [ride];
}
class ArrivedAtPickupState extends RideState {
  final RideRequestModel ride;
  /// Server-computed seconds already spent waiting. 0 on a fresh arrival; set
  /// when the server reports the driver had already arrived (a resumed app).
  final int waitingSec;
  ArrivedAtPickupState(this.ride, {this.waitingSec = 0});
  @override List<Object?> get props => [ride, waitingSec];
}
/// The server refused or could not record the arrival. The screen stays on the
/// "arrive" step and says why, instead of pretending the driver had arrived.
class ArriveFailedState extends RideState {
  final RideRequestModel ride;
  final String message;
  // RideState is Equatable and Bloc drops a state equal to the current one, so
  // without this a second identical failure would never reach the screen.
  final int _nonce = DateTime.now().microsecondsSinceEpoch;
  ArriveFailedState(this.ride, this.message);
  @override List<Object?> get props => [ride, message, _nonce];
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
    on<AcceptRideEvent>(_onAccept);
    on<RejectRideEvent>(_onReject);
    on<ArrivedEvent>(_onArrived);
    on<StartRideEvent>(_onStart);
    on<EndRideEvent>(_onEnd);
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
    final ride = currentRide!;
    Map<String, dynamic> res;
    try {
      res = await DriverApiService.arrivedRide(ride.id);
    } catch (_) {
      res = {'error': 'Could not reach the server. Check your connection and try again.'};
    }
    // This used to swallow every failure and emit "arrived" regardless, so on a
    // dead network the driver's screen said they had arrived while the server —
    // and the rider — still had them on the way.
    if (res['error'] != null) {
      emit(ArriveFailedState(ride, res['error'].toString()));
      return;
    }
    emit(ArrivedAtPickupState(ride, waitingSec: (res['waitingSec'] as num?)?.toInt() ?? 0));
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
