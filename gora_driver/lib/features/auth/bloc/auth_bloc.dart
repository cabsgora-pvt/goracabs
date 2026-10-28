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
// Documents saved but bank details (the last registration step) not yet —
// server registrationStep == 'bank'. Resumes at the bank page instead of
// sending the driver back to onboarding/login.
class RegistrationBankPendingState extends AuthState {}
/// Registration started but not finished, at a step before bank details.
class RegistrationResumeState extends AuthState {
  final ResumeStep step;
  final Map<String, dynamic> driver;
  RegistrationResumeState(this.step, this.driver);
  @override List<Object?> get props => [step];
}

/// Where an unfinished registration picks up again.
enum ResumeStep { personal, face, vehicle, documents }

/// The registration page to resume at for [driver], from the server's own
/// registrationStep — the only steps it writes are 'otp' (account created),
/// 'vehicle' (personal details saved), 'documents' (vehicle saved), 'bank'
/// (documents saved) and 'submitted'. The selfie writes no step of its own,
/// only faceSignatureSavedAt, so 'vehicle' without it means the selfie is
/// still to do. Null for 'bank', 'submitted' and any value not listed here.
ResumeStep? resumeStepFor(Map<String, dynamic>? driver) {
  if (driver == null) return null;
  final step = (driver['registrationStep'] ?? '').toString();
  final faceDone = driver['faceSignatureSavedAt'] != null;
  switch (step) {
    case '':
    case 'otp':
    case 'personal':
      return ResumeStep.personal;
    case 'face':
      return ResumeStep.face;
    case 'vehicle':
      return faceDone ? ResumeStep.vehicle : ResumeStep.face;
    case 'documents':
      return ResumeStep.documents;
    default:
      return null;
  }
}

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
          } else if (regStep == 'bank') {
            emit(RegistrationBankPendingState());
            return;
          }
          // Closed part-way through (after the selfie, after the vehicle…):
          // resume at that step instead of sending a signed-in driver back to
          // onboarding and login.
          final resume = resumeStepFor(driverData);
          if (resume != null) {
            emit(RegistrationResumeState(resume, driverData));
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
