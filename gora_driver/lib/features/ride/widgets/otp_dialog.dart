import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A 4-digit code the driver types: the rider's OTP to start a trip, the
/// receiver's to hand over a parcel. Resolves to what was typed, or null on
/// Cancel.
///
/// Holds no controller: the field keeps its own text and this keeps what was
/// typed. Both OTP dialogs used to create a controller and dispose it the
/// moment the dialog closed — while the field was still on screen animating
/// out — which failed with "A TextEditingController was used after being
/// disposed".
class OtpDialog extends StatefulWidget {
  final String title;
  final String label;
  final String hint;
  final String action;
  const OtpDialog({super.key, required this.title, required this.label, required this.hint, required this.action});

  static Future<String?> show(BuildContext context,
          {required String title, required String label, required String hint, required String action}) =>
      showDialog<String>(
        context: context,
        builder: (_) => OtpDialog(title: title, label: label, hint: hint, action: action),
      );

  @override
  State<OtpDialog> createState() => _OtpDialogState();
}

/// Digits in a ride / parcel OTP. At this many the dialog submits itself.
const otpLength = 4;

/// The pause between the last digit and the automatic submit, so the driver
/// sees the full code before the dialog closes.
const otpAutoSubmitAfter = Duration(milliseconds: 250);

class _OtpDialogState extends State<OtpDialog> {
  String _otp = '';
  bool _done = false;
  Timer? _auto;

  @override
  void dispose() {
    _auto?.cancel();
    super.dispose();
  }

  void _submit() {
    if (_done) return;
    _done = true;
    _auto?.cancel();
    Navigator.pop(context, _otp);
  }

  void _changed(String v) {
    _otp = v.trim();
    _auto?.cancel();
    if (_otp.length == otpLength) _auto = Timer(otpAutoSubmitAfter, () { if (mounted) _submit(); });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700)),
    content: TextField(
      // The keypad is up the moment the dialog opens, digits only, and the
      // code goes in by itself at the 4th digit.
      autofocus: true,
      onChanged: _changed,
      onSubmitted: (_) => _submit(),
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      maxLength: otpLength,
      decoration: InputDecoration(labelText: widget.label, hintText: widget.hint),
      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 8),
    ),
    actions: [
      TextButton(onPressed: () { _done = true; _auto?.cancel(); Navigator.pop(context); }, child: const Text('Cancel')),
      ElevatedButton(onPressed: _submit, child: Text(widget.action)),
    ],
  );
}
