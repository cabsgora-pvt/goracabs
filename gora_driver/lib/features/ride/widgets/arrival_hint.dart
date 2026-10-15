import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

/// A "you have reached …" nudge that goes once the driver has done what it
/// asks.
///
/// A snack bar's timer does not run under a dialog or a pushed page, so a nudge
/// already acted on was still showing afterwards: "swipe Arrived" as the trip
/// started, "collect the parcel" after collecting, "enter the OTP" on the fare
/// screen. Only a snack bar on screen can be closed; one still waiting its turn
/// is closed the moment it appears.
class ArrivalHint {
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _shown;
  bool _visible = false;
  bool _done = false;

  void show(BuildContext context, String text) {
    dismiss();
    _visible = false;
    _done = false;
    final messenger = ScaffoldMessenger.of(context);
    late final ScaffoldFeatureController<SnackBar, SnackBarClosedReason> hint;
    hint = messenger.showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: AppColors.green,
      onVisible: () {
        if (!identical(_shown, hint)) return;
        _visible = true;
        // Acted on while it waited its turn: nothing left to say.
        if (_done) {
          _shown = null;
          hint.close();
        }
      },
    ));
    _shown = hint;
    hint.closed.then((_) { if (identical(_shown, hint)) _shown = null; });
  }

  /// The driver has done what it asked.
  void dismiss() {
    final hint = _shown;
    if (hint == null) return;
    if (_visible) {
      _shown = null;
      hint.close();
    } else {
      _done = true;
    }
  }
}
