import 'package:flutter/material.dart';
import '../auth/bloc/auth_bloc.dart';
import 'document_upload_page.dart';
import 'face_capture_page.dart';
import 'personal_details_page.dart';
import 'vehicle_selection_page.dart';

/// Opens the registration page for [step] as the only route — used from the
/// splash check and from OTP login, so an unfinished registration resumes
/// where the server says it stopped. Client routing only: the step itself
/// comes from the server ([resumeStepFor]).
void openRegistrationStep(NavigatorState nav, ResumeStep step, {String phone = '', Map<String, dynamic>? driver}) {
  final (String route, Object? args) = switch (step) {
    ResumeStep.personal => (PersonalDetailsPage.route, {'phone': phone}),
    // The selfie page hands these on to vehicle selection, as it does when
    // reached straight from personal details.
    ResumeStep.face => (FaceCapturePage.route, {'zoneId': driver?['zoneId'], 'zoneName': driver?['zoneName']}),
    ResumeStep.vehicle => (VehicleSelectionPage.route, null),
    ResumeStep.documents => (DocumentUploadPage.route, null),
  };
  nav.pushNamedAndRemoveUntil(route, (_) => false, arguments: args);
}
