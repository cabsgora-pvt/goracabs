import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// What the server's refusal codes mean to the driver, for the in-trip actions
// (start / deliver OTP, arrived, stops, rental / hire / parcel actions).
// ─────────────────────────────────────────────────────────────────────────────

/// The line to show for a refused trip action. The server's text is used for
/// a code with nothing better to say.
String rideActionError(Map<String, dynamic> res) {
  final code = (res['code'] ?? '').toString();
  final server = (res['error'] ?? '').toString();
  switch (code) {
    case 'OTP_INVALID':
    case 'OTP_LOCKED':
    case 'OTP_RATE_LIMITED':
    case 'OTP_MISSING':
      return otpErrorMessage(res);
    case 'TOO_FAR_FROM_PICKUP':
      final km = res['distanceKm'];
      return km is num
          ? 'You are ${km.toStringAsFixed(1)} km from pickup. Get closer to mark arrived.'
          : (server.isNotEmpty ? server : 'You are too far from the pickup.');
    case 'NOT_ONGOING':
      return 'This trip is not in progress any more. Go back and refresh.';
    case 'STOP_DONE':
      return 'This stop is already done.';
    case 'STOP_ALREADY_REACHED':
      return 'You are already marked at this stop.';
    case 'STOP_NOT_REACHED':
      return 'Mark the stop as reached first.';
    case 'STOP_CHANGED':
    case 'DELIVERY_CHANGED':
      return 'The trip changed — go back and open it again.';
    case 'NOT_COLLECTED':
      return 'Collect the parcel first.';
    case 'DELIVERY_FINISHED':
      return 'This delivery is already finished.';
    case 'REASON_REQUIRED':
      return 'Choose why the delivery failed.';
    case 'PHOTO_REQUIRED':
      return 'Take a photo to mark the delivery as failed.';
  }
  return server.isNotEmpty ? server : 'Something went wrong. Please try again.';
}

/// The OTP refusal, with attempts left / locked guidance.
String otpErrorMessage(Map<String, dynamic> res) {
  switch ((res['code'] ?? '').toString()) {
    case 'OTP_INVALID':
      final left = res['attemptsLeft'];
      if (left is num) {
        return left <= 0
            ? 'Wrong OTP. The code is now locked — ask the rider to contact support.'
            : 'Wrong OTP. ${left.toInt()} ${left == 1 ? 'attempt' : 'attempts'} left.';
      }
      return 'Wrong OTP. Please check and try again.';
    case 'OTP_LOCKED':
      return otpLockedMessage;
    case 'OTP_RATE_LIMITED':
      return 'Too many wrong OTPs. Wait a few minutes and try again.';
    case 'OTP_MISSING':
      return 'This trip has no OTP. Please contact support.';
  }
  final e = (res['error'] ?? '').toString();
  return e.isNotEmpty ? e : 'Invalid OTP';
}

const otpLockedMessage = 'Too many wrong OTPs — the code is locked. Ask the rider to contact support.';

// ── Rental / hire extension ──────────────────────────────────────────────────

/// The server accepts 1..12 whole hours.
const maxExtendHours = 12;
const extendOptions = [1, 2, 4, 6];
bool validExtraHours(int h) => h >= 1 && h <= maxExtendHours;

/// An extension waiting for the rider: {hours, amount, addKm, expiresAt}.
class PendingExtension {
  final int hours;
  final num amount;
  final num addKm;
  final DateTime? expiresAt;
  const PendingExtension({required this.hours, required this.amount, this.addKm = 0, this.expiresAt});

  static PendingExtension? tryParse(dynamic v) {
    if (v is! Map) return null;
    final h = v['hours'];
    if (h is! num) return null;
    final exp = DateTime.tryParse((v['expiresAt'] ?? '').toString())?.toLocal();
    // Lapsed: the rider did not confirm in time.
    if (exp != null && exp.isBefore(DateTime.now())) return null;
    return PendingExtension(
      hours: h.toInt(),
      amount: v['amount'] is num ? v['amount'] as num : 0,
      addKm: v['addKm'] is num ? v['addKm'] as num : 0,
      expiresAt: exp,
    );
  }
}

/// The extension an 'extend' reply asked the rider to confirm.
PendingExtension? extensionFrom(Map<String, dynamic> res) {
  if (res['awaitingRiderConfirmation'] != true) return null;
  return PendingExtension.tryParse(res['pendingExtension']);
}

String waitingForRiderText(PendingExtension e) =>
    'Waiting for rider to confirm (₹${e.amount.round()}) — +${e.hours} hr';

class PendingExtensionNote extends StatelessWidget {
  final PendingExtension ext;
  const PendingExtensionNote({super.key, required this.ext});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
    child: Row(children: [
      const Icon(Icons.hourglass_top_rounded, size: 18, color: AppColors.primary),
      const SizedBox(width: 8),
      Expanded(child: Text(waitingForRiderText(ext),
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.primary))),
    ]),
  );
}
