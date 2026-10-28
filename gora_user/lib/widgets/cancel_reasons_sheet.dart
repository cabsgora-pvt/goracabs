import 'package:flutter/material.dart';

import 'ride_ui/ride_ui.dart';

/// The one "why are you cancelling?" sheet, shared by the booking screen and the
/// live ride screen. They used to differ: one asked for a reason and a confirm,
/// the other cancelled the moment a reason was tapped — an accidental tap was a
/// cancelled ride.
///
/// Resolves to the chosen reason once the rider confirms, or null when they
/// back out ("Don't cancel", system back, or a tap outside). The caller makes
/// the cancel request and decides what happens next, so each screen keeps its
/// own API call and post-cancel behaviour.
///
/// [cancelFee] above zero shows the fee the server will apply, before the
/// rider commits.
Future<String?> showCancelReasonsSheet(
  BuildContext context, {
  required List<String> reasons,
  num cancelFee = 0,
}) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheet) => CancelReasonsSheet(reasons: reasons, cancelFee: cancelFee),
    );

class CancelReasonsSheet extends StatefulWidget {
  final List<String> reasons;
  final num cancelFee;
  const CancelReasonsSheet({super.key, required this.reasons, this.cancelFee = 0});

  @override
  State<CancelReasonsSheet> createState() => _CancelReasonsSheetState();
}

class _CancelReasonsSheetState extends State<CancelReasonsSheet> {
  String? _reason;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      child: RideSheetContainer(
        radius: 24,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SheetHandle(bottom: 16),
                Text('Cancel Ride', style: RideUi.title(context, size: 22)),
                const SizedBox(height: 4),
                Text('Please select a reason for cancellation', style: RideUi.caption(context, size: 13.5)),
                if (widget.cancelFee > 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.info_outline, size: 18, color: Colors.orange),
                      const SizedBox(width: 8),
                      Expanded(child: Text(
                        'A ₹${widget.cancelFee.toStringAsFixed(0)} cancellation fee applies — your driver is already on the way.',
                        style: const TextStyle(fontSize: 12.5, color: Colors.orange, fontWeight: FontWeight.w600),
                      )),
                    ]),
                  ),
                ],
                const SizedBox(height: 10),
                for (var i = 0; i < widget.reasons.length; i++) ...[
                  if (i > 0) const RideDivider(),
                  _reasonTile(widget.reasons[i]),
                ],
                const SizedBox(height: 16),
                PrimaryRideButton(
                  label: 'Confirm Cancellation',
                  color: const Color(0xFFD32F2F),
                  onPressed: _reason == null ? null : () => Navigator.pop(context, _reason),
                ),
                const SizedBox(height: 4),
                RideTextAction(
                  label: "Don't cancel",
                  color: RideUi.muted(context),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _reasonTile(String r) {
    final sel = _reason == r;
    return InkWell(
      onTap: () => setState(() => _reason = r),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(children: [
          Expanded(child: Text(r, style: RideUi.body(context, size: 15, weight: FontWeight.w600))),
          Icon(sel ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: sel ? RideUi.accent(context) : RideUi.muted(context), size: 22),
        ]),
      ),
    );
  }
}
