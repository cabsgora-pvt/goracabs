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

/// What the rider chose on the "No driver found" dialog.
enum NoDriverChoice { tryAgain, changeRide }

/// Tells the rider no driver was found.
///
/// With [canTryAgain] the rider gets "Try again", which books the same trip
/// again (with a fresh quote), and a separate "Change ride" to go back and pick
/// something else. "Try again" used to just close the screen, so the booking
/// the rider had made was lost and had to be entered from scratch. A ride
/// reopened from home has no booking to repeat, so it offers "OK" alone.
/// Completes with the choice; system Back counts as [NoDriverChoice.changeRide].
Future<NoDriverChoice> showNoDriverFoundDialog(BuildContext context, {bool canTryAgain = false}) async {
  final choice = await showDialog<NoDriverChoice>(
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
        if (canTryAgain) ...[
          PrimaryRideButton(
            label: 'Try again',
            height: 48,
            onPressed: () => Navigator.of(ctx).pop(NoDriverChoice.tryAgain),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.of(ctx).pop(NoDriverChoice.changeRide),
              child: const Text('Change ride'),
            ),
          ),
        ] else
          PrimaryRideButton(
            label: 'OK',
            height: 48,
            onPressed: () => Navigator.of(ctx).pop(NoDriverChoice.changeRide),
          ),
      ],
    ),
  );
  return choice ?? NoDriverChoice.changeRide;
}
