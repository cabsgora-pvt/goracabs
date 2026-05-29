import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../mock/mock_data.dart';
import '../../../models/models.dart';
import '../../../services/driver_api_service.dart';

// Events
abstract class AuthEvent extends Equatable {
  @override List<Object?> get props => [];
}
class LoginEvent extends AuthEvent {
  final String phone;
  LoginEvent(this.phone);
  @override List<Object?> get props => [phone];
}
class VerifyOtpEvent extends AuthEvent {
  final String otp;
  VerifyOtpEvent(this.otp);
  @override List<Object?> get props => [otp];
}
class CheckAuthEvent extends AuthEvent {}
class LogoutEvent extends AuthEvent {}

// States
abstract class AuthState extends Equatable {
  @override List<Object?> get props => [];
}
class AuthInitial extends AuthState {}
class AuthLoading extends AuthState {}
class OtpSentState extends AuthState {
  final String phone;
  OtpSentState(this.phone);
  @override List<Object?> get props => [phone];
}
class AuthenticatedState extends AuthState {
  final DriverModel driver;
  AuthenticatedState(this.driver);
  @override List<Object?> get props => [driver];
}
class UnauthenticatedState extends AuthState {}
class AuthErrorState extends AuthState {
  final String message;
  AuthErrorState(this.message);
  @override List<Object?> get props => [message];
}
class RegistrationSubmittedState extends AuthState {}
class RejectionState extends AuthState {
  final String reason;
  final Map<String, dynamic>? driver;
  RejectionState(this.reason, {this.driver});
  @override List<Object?> get props => [reason];
}

// BLoC
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc() : super(AuthInitial()) {
    on<CheckAuthEvent>(_onCheck);
    on<LoginEvent>(_onLogin);
    on<VerifyOtpEvent>(_onVerify);
    on<LogoutEvent>(_onLogout);
  }

  Future<void> _onCheck(CheckAuthEvent e, Emitter emit) async {
    // Try real API token first
    final token = await DriverApiService.getToken();
    if (token != null) {
      try {
        final res = await DriverApiService.getProfile();
        final driverData = res['driver'] as Map<String, dynamic>?;
        if (driverData != null) {
          final status = driverData['status'] as String?;
          final regStep = driverData['registrationStep'] as String?;
          if (status == 'approved') {
            final driver = DriverModel(
              id: driverData['_id'] as String? ?? '',
              name: driverData['name'] as String? ?? '',
              phone: driverData['phone'] as String? ?? '',
              email: driverData['email'] as String? ?? '',
              profilePic: '',
              vehicleNumber: driverData['vehicleRegistrationNumber'] as String? ??
                  driverData['vehicleNumber'] as String? ?? '',
              vehicleModel: driverData['vehicleModel'] as String? ?? '',
              vehicleType: driverData['selectedVehicleTypeName'] as String? ??
                  driverData['vehicleType'] as String? ?? '',
              rating: driverData['rating']?.toString() ?? '0',
              totalRides: driverData['totalRides']?.toString() ?? '0',
              status: status ?? 'pending',
              walletBalance: (driverData['walletBalance'] as num?)?.toDouble() ?? 0.0,
              isOnline: driverData['isOnline'] as bool? ?? false,
              isApproved: true,
            );
            emit(AuthenticatedState(driver));
            return;
          } else if (status == 'rejected') {
            emit(RejectionState(
              driverData['rejectionReason'] as String? ?? 'Application rejected.',
              driver: driverData,
            ));
            return;
          } else if (regStep == 'submitted') {
            emit(RegistrationSubmittedState());
            return;
          }
        }
      } catch (_) {
        // Token exists but network error — go to unauthenticated
        emit(UnauthenticatedState());
        return;
      }
    }

    emit(UnauthenticatedState());
  }

  Future<void> _onLogin(LoginEvent e, Emitter emit) async {
    emit(AuthLoading());
    // MockAuthService.login is a no-op; OTP is sent via DriverApiService in UI
    await MockAuthService.login(e.phone);
    emit(OtpSentState(e.phone));
  }

  Future<void> _onVerify(VerifyOtpEvent e, Emitter emit) async {
    emit(AuthLoading());
    final ok = await MockAuthService.verifyOtp(e.otp);
    if (ok) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('logged_in', true);
      final driver = await MockAuthService.getProfile();
      emit(AuthenticatedState(driver));
    } else {
      emit(AuthErrorState('Invalid OTP. Use 1234'));
    }
  }

  Future<void> _onLogout(LogoutEvent e, Emitter emit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('logged_in', false);
    await DriverApiService.clearToken();
    emit(UnauthenticatedState());
  }
}
