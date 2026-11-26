import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../models/models.dart';
import '../../../services/driver_api_service.dart';
import '../logic/ride_actions.dart';

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
/// The server did not record the end of the trip. The screen stays on the trip
/// and says why, instead of showing an invoice for a ride that is still ongoing.
class EndFailedState extends RideState {
  final RideRequestModel ride;
  final String message;
  // Same as ArriveFailedState: a second identical failure must still emit.
  final int _nonce = DateTime.now().microsecondsSinceEpoch;
  EndFailedState(this.ride, this.message);
  @override List<Object?> get props => [ride, message, _nonce];
}
class RideRejectedState extends RideState {}
/// /start answered 409 RIDE_CANCELLED: the rider cancelled while the driver
/// was entering the OTP. The trip screen closes.
class RideCancelledState extends RideState {
  final String message;
  RideCancelledState([this.message = rideCancelledText]);
  @override List<Object?> get props => [message];
}
// Another driver already took the ride (HTTP 409)
class RideTakenState extends RideState {}
// The trip did not start: wrong OTP, or the server could not be reached.
class OtpErrorState extends RideState {
  final RideRequestModel ride;
  final String message;
  /// The code is locked (too many wrong tries): support has to unlock it.
  final bool locked;
  // Without this a second wrong OTP equalled the first and was never shown.
  final int _nonce = DateTime.now().microsecondsSinceEpoch;
  OtpErrorState(this.ride, [this.message = 'Invalid OTP', this.locked = false]);
  @override List<Object?> get props => [ride, message, locked, _nonce];
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
      // A repeat accept of a ride already ours is a success too.
      if (res['success'] == true || res['repeated'] == true) { emit(RideAcceptedState(currentRide!)); return; }
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
      // TOO_FAR_FROM_PICKUP → "You are X km from pickup".
      emit(ArriveFailedState(ride, rideActionError(res)));
      return;
    }
    emit(ArrivedAtPickupState(ride, waitingSec: (res['waitingSec'] as num?)?.toInt() ?? 0));
  }

  Future<void> _onStart(StartRideEvent e, Emitter emit) async {
    try {
      final res = await DriverApiService.startRide(currentRide!.id, e.otp);
      if (res['success'] == true) {
        emit(RideStartedState(currentRide!));
      } else if (res['code'] == 'RIDE_CANCELLED') {
        emit(RideCancelledState());
      } else {
        // Attempts left / locked / rate-limited, as the server counts them.
        emit(OtpErrorState(currentRide!, otpErrorMessage(res), res['code'] == 'OTP_LOCKED'));
      }
    } catch (_) {
      // A dropped connection is not a wrong OTP; telling the driver it was
      // sends them back to the rider for a code that was right.
      emit(OtpErrorState(currentRide!, 'Could not reach the server. Check your connection and try again.'));
    }
  }

  Future<void> _onEnd(EndRideEvent e, Emitter emit) async {
    final ride = currentRide!;
    emit(RideLoading());
    Map<String, dynamic> res;
    try {
      res = await DriverApiService.completeRide(ride.id);
    } catch (_) {
      res = const {'error': 'Could not reach the server. Check your connection and try again.'};
    }
    var error = res['error']?.toString();
    if (error == 'Already completed') {
      // Settled by an earlier attempt whose reply never arrived: the ride
      // itself holds what it paid.
      try {
        res = await DriverApiService.getRide(ride.id);
        error = res['error']?.toString();
      } catch (_) {
        error = 'Could not reach the server. Check your connection and try again.';
      }
    }
    // This used to emit "ended" on any failure, so the invoice showed the full
    // fare as earnings at 0% commission while the server still had the trip
    // ongoing. Stay on the trip and say why; the driver swipes again.
    if (error != null) {
      emit(EndFailedState(ride, error));
      return;
    }
    emit(RideEndedState(
      ride,
      adminProfit: _num(res['adminProfit'] ?? res['commissionAmount']),
      driverEarning: _num(res['driverEarning']),
    ));
  }

  static num _num(dynamic v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;
}
