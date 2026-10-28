import 'package:flutter/material.dart';
import 'ride_ui/ride_ui.dart';

/// What the rider is told when the server closed their search.
const kNoDriverMessage = 'No drivers available right now. Please try again.';

/// True when the SERVER closed this ride because no driver took it.
///
/// The app never decides this itself — there is no client-side timeout. The
/// backend cancels a ride still pending a few minutes after it became due
/// (cancelledBy 'system', reason 'No driver found'), and the screens only react
/// to that state on their next poll.
///
/// The reason is checked as well as cancelledBy: the server also cancels with
/// cancelledBy 'system' when a driver fails a mid-ride face check, and that
/// must not read as "no drivers available".
bool isNoDriverFound(Map<String, dynamic> ride) =>
    (ride['status'] ?? '').toString() == 'cancelled' &&
    (ride['cancelledBy'] ?? '').toString() == 'system' &&
    (ride['cancellationReason'] ?? '').toString() == 'No driver found';

/// Tells the rider no driver was found, with a single "Try again" action.
/// Completes when the rider dismisses it (Try again, or system Back).
Future<void> showNoDriverFoundDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.search_off_rounded, size: 44, color: RideUi.ink(ctx)),
        const SizedBox(height: 12),
        Text('No driver found', textAlign: TextAlign.center, style: RideUi.title(ctx, size: 19)),
        const SizedBox(height: 8),
        Text(kNoDriverMessage, textAlign: TextAlign.center, style: RideUi.body(ctx, size: 14)),
      ]),
      actions: [
        PrimaryRideButton(
          label: 'Try again',
          height: 48,
          onPressed: () => Navigator.of(ctx).pop(),
        ),
      ],
    ),
  );
}
