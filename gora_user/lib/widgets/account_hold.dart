import 'package:flutter/material.dart';
import '../screens/support_screen.dart';
import 'ride_ui/ride_ui.dart';

/// The server refused a booking because an admin put this account on hold:
/// 403 {accountHold: true, error: "Your account is on hold: …"}.
bool isAccountHoldResponse(Map<String, dynamic> res) => res['accountHold'] == true;

const _holdRed = Color(0xFFD32F2F);

/// Explains a hold in a dialog — a held rider needs to know it is not a
/// network blip and that retrying will not help — with a way to support.
Future<void> showAccountHoldDialog(BuildContext context, String message) {
  final text = message.trim().isNotEmpty
      ? message.trim()
      : 'Your account is on hold. Please contact support.';
  return showDialog<void>(
    context: context,
    builder: (dctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      icon: const Icon(Icons.lock_clock_rounded, color: _holdRed, size: 36),
      title: const Text('Account on hold', style: TextStyle(fontWeight: FontWeight.w800)),
      content: Text(
        "$text\n\nYou can't book rides until the hold is lifted.",
        textAlign: TextAlign.center,
        style: RideUi.body(dctx, size: 14, weight: FontWeight.w500).copyWith(height: 1.4),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(dctx).pop();
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SupportScreen()));
          },
          child: const Text('Contact support'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(dctx).pop(),
          style: ElevatedButton.styleFrom(backgroundColor: RideUi.navy, foregroundColor: Colors.white),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Red banner for the home screen while the account is on hold.
class AccountHoldBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onContactSupport;
  const AccountHoldBanner({super.key, required this.message, this.onContactSupport});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      key: const ValueKey('account-hold-banner'),
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 10),
      decoration: BoxDecoration(
        color: dark ? _holdRed.withValues(alpha: 0.22) : const Color(0xFFFDECEC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _holdRed.withValues(alpha: 0.45)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.error_outline_rounded, color: _holdRed, size: 22),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Account on hold',
                style: TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w800, color: dark ? Colors.red.shade200 : _holdRed)),
            const SizedBox(height: 3),
            Text(message, style: RideUi.body(context, size: 12.5, weight: FontWeight.w500).copyWith(height: 1.35)),
            if (onContactSupport != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onContactSupport,
                  style: TextButton.styleFrom(
                    foregroundColor: dark ? Colors.red.shade200 : _holdRed,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                  child: const Text('Contact support'),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}
