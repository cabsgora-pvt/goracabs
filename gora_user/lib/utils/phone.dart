/// The 10-digit Indian mobile number in [input], or null.
///
/// The server's send-otp and verify-otp accept only these (6–9 first digit),
/// so the app checks before asking: a pasted "+91 98765 43210" or
/// "098765 43210" becomes "9876543210"; a landline or a short number is
/// refused here with a clear message instead of a round trip.
String? indianMobile(String input) {
  var d = input.replaceAll(RegExp(r'[\s\-()]'), '');
  if (d.startsWith('+')) d = d.substring(1);
  if (!RegExp(r'^\d+$').hasMatch(d)) return null;
  if (d.length == 12 && d.startsWith('91')) d = d.substring(2);
  if (d.length == 11 && d.startsWith('0')) d = d.substring(1);
  return RegExp(r'^[6-9]\d{9}$').hasMatch(d) ? d : null;
}
