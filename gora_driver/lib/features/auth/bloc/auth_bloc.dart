import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../models/models.dart';
import '../../../services/driver_api_service.dart';

// Events
//
// Login/OTP themselves are NOT handled here — login_page.dart and
// driver_otp_page.dart call DriverApiService and DriverProvider directly.
// This bloc only covers the app-restart session check and logout.
abstract class AuthEvent extends Equatable {
  @override List<Object?> get props => [];
}
class CheckAuthEvent extends AuthEvent {}
class LogoutEvent extends AuthEvent {}

// States
abstract class AuthState extends Equatable {
  @override List<Object?> get props => [];
}
class AuthInitial extends AuthState {}
class AuthenticatedState extends AuthState {
  final DriverModel driver;
  AuthenticatedState(this.driver);
  @override List<Object?> get props => [driver];
}
class UnauthenticatedState extends AuthState {}
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
            emit(AuthenticatedState(DriverModel.fromApi(driverData)));
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

  Future<void> _onLogout(LogoutEvent e, Emitter emit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('logged_in', false);
    await DriverApiService.clearToken();
    emit(UnauthenticatedState());
  }
}
