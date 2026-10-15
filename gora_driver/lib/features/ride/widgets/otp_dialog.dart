import 'package:flutter/material.dart';

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

class _OtpDialogState extends State<OtpDialog> {
  String _otp = '';

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700)),
    content: TextField(
      onChanged: (v) => _otp = v.trim(),
      keyboardType: TextInputType.number,
      maxLength: 4,
      decoration: InputDecoration(labelText: widget.label, hintText: widget.hint),
      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 8),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      ElevatedButton(onPressed: () => Navigator.pop(context, _otp), child: Text(widget.action)),
    ],
  );
}
