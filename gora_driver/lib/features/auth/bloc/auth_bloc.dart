import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../mock/mock_data.dart';
import '../../../models/models.dart';

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

// BLoC
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc() : super(AuthInitial()) {
    on<CheckAuthEvent>(_onCheck);
    on<LoginEvent>(_onLogin);
    on<VerifyOtpEvent>(_onVerify);
    on<LogoutEvent>(_onLogout);
  }

  Future<void> _onCheck(CheckAuthEvent e, Emitter emit) async {
    final prefs = await SharedPreferences.getInstance();
    final loggedIn = prefs.getBool('logged_in') ?? false;
    if (loggedIn) {
      final driver = await MockAuthService.getProfile();
      emit(AuthenticatedState(driver));
    } else {
      emit(UnauthenticatedState());
    }
  }

  Future<void> _onLogin(LoginEvent e, Emitter emit) async {
    emit(AuthLoading());
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
    emit(UnauthenticatedState());
  }
}
