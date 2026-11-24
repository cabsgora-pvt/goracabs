// ─────────────────────────────────────────────────────────────────────────────
// What a refused "accept" means for the request screen.
//
// POST /rides/:id/accept answers a refusal with {error, code}. Some codes are
// about this one request (another captain has it, wrong vehicle, too far …) —
// that card goes. Some are about the driver (not approved, on hold, offline,
// wallet blocked …) — no request can be accepted, so the screen closes. Two are
// "try again" (another accept for this ride is still in flight).
// ─────────────────────────────────────────────────────────────────────────────

enum AcceptAction {
  /// Accepted (or already ours — a repeated accept): open the trip.
  open,
  /// Refused for this request only: take its card off.
  dropCard,
  /// Refused for this request for now (a scheduled ride not open yet): take
  /// the card off, but it may be offered again later.
  dismissCard,
  /// Nothing wrong with the request: leave it up so the driver can retry.
  keepCard,
  /// Refused for every request: close the request screen.
  closeAll,
}

class AcceptOutcome {
  final AcceptAction action;
  final String message;
  const AcceptOutcome(this.action, [this.message = '']);
}

/// The driver-facing line for each refusal code. The server's own text is used
/// for a code not listed here.
const acceptMessages = <String, String>{
  'NOT_APPROVED': 'Your account is not approved yet. You can accept trips once it is approved.',
  'FACE_VERIFICATION_REQUIRED': 'Verify your face again before accepting trips.',
  'ACCOUNT_HOLD': 'Your account is on hold. Please contact support.',
  'OFFLINE': 'You are offline. Go online to accept trips.',
  'WALLET_BLOCKED': 'Your wallet balance is too low. Recharge to accept trips.',
  'VEHICLE_MISMATCH': 'This trip needs a different vehicle type.',
  'SERVICE_NOT_ALLOWED': 'Your vehicle cannot take this kind of trip.',
  'SERVICE_NOT_ENABLED': 'Turn this service on in Trip preferences to take these trips.',
  'WRONG_ZONE': 'This trip is outside your zone.',
  'OUT_OF_RANGE': 'You are too far from this pickup.',
  'CASH_PAUSED': 'Your wallet is negative, so cash trips are paused. Recharge to take cash trips.',
  'FEMALE_DRIVER_REQUESTED': 'The rider asked for a female captain.',
  'REJECTED': 'You declined this trip.',
  'OFFERED_TO_OTHER': 'This trip is being offered to another captain.',
  'NOT_OPEN_YET': 'This scheduled trip is not open for accepting yet.',
  'DRIVER_BUSY': 'Finish your current trip before accepting another.',
  'RIDE_TAKEN': 'Another captain took this trip.',
  'ACCEPT_IN_PROGRESS': 'Still confirming this trip — try again in a moment.',
};

const _closeAll = {'NOT_APPROVED', 'FACE_VERIFICATION_REQUIRED', 'ACCOUNT_HOLD', 'OFFLINE', 'WALLET_BLOCKED', 'DRIVER_BUSY'};
const _keep = {'ACCEPT_IN_PROGRESS'};
const _dismiss = {'NOT_OPEN_YET'};

AcceptOutcome acceptOutcome(Map<String, dynamic> r) {
  if (r['success'] == true || r['repeated'] == true) return const AcceptOutcome(AcceptAction.open);
  final code = (r['code'] ?? '').toString();
  final server = (r['error'] ?? '').toString();
  final msg = acceptMessages[code] ?? (server.isNotEmpty ? server : 'Could not accept this trip');
  if (r['accountHold'] == true || _closeAll.contains(code)) return AcceptOutcome(AcceptAction.closeAll, msg);
  if (_keep.contains(code)) return AcceptOutcome(AcceptAction.keepCard, msg);
  if (_dismiss.contains(code)) return AcceptOutcome(AcceptAction.dismissCard, msg);
  // A 5xx or an unreadable reply is not a refusal of this trip.
  final status = r['_status'];
  if (code.isEmpty && status is int && status >= 500) {
    return AcceptOutcome(AcceptAction.keepCard, server.isNotEmpty ? server : 'Server error — try again');
  }
  return AcceptOutcome(AcceptAction.dropCard, msg);
}
