import 'package:flutter/services.dart';

import 'phone.dart';

/// Keeps a phone field to the 10 digits of an Indian mobile number.
///
/// Typing lets through digits only. A paste of "+91 98765 43210",
/// "098765-43210" or "91 9876543210" becomes "9876543210" (via
/// [indianMobile]) instead of being cut to "+91 98765 4" by the length limit.
class IndianPhoneInputFormatter extends TextInputFormatter {
  const IndianPhoneInputFormatter();

  /// The digits to keep for [raw]: the mobile number when [raw] holds one in
  /// any common written form, else its digits, at most 10.
  static String normalize(String raw) {
    final mobile = indianMobile(raw);
    if (mobile != null) return mobile;
    var d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.length > 10) {
      if (d.length == 12 && d.startsWith('91')) {
        d = d.substring(2);
      } else if (d.length == 11 && d.startsWith('0')) {
        d = d.substring(1);
      }
    }
    return d.length > 10 ? d.substring(0, 10) : d;
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final out = normalize(newValue.text);
    if (out == newValue.text) return newValue;
    return TextEditingValue(
      text: out,
      selection: TextSelection.collapsed(offset: out.length),
    );
  }
}
