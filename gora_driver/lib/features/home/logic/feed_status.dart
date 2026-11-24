import 'package:flutter/foundation.dart';

/// Why the request feed is empty when the server says it is empty on purpose.
///
/// /rides/driver/pending answers {rides: [], notApproved | offline | hold |
/// busy | walletBlocked: true} when this driver cannot get requests right now.
/// The home screen showed nothing at all, so an online driver with a blocked
/// wallet waited for trips that could never come.
class FeedBlock {
  final String kind;
  final String title;
  final String message;
  const FeedBlock(this.kind, this.title, this.message);

  @override
  bool operator ==(Object other) =>
      other is FeedBlock && other.kind == kind && other.title == title && other.message == message;
  @override
  int get hashCode => Object.hash(kind, title, message);
}

FeedBlock? feedBlockFrom(Map<String, dynamic> res) {
  if (res['notApproved'] == true) {
    return const FeedBlock('notApproved', 'Account not approved yet',
        'You will get trip requests once your account is approved.');
  }
  if (res['hold'] == true) {
    return const FeedBlock('hold', 'Account on hold',
        'No trip requests while your account is on hold. Please contact support.');
  }
  if (res['walletBlocked'] == true) {
    final reason = (res['reason'] ?? '').toString();
    return FeedBlock('walletBlocked', 'Wallet balance too low',
        reason.isNotEmpty ? reason : 'Recharge your wallet to receive trip requests.');
  }
  if (res['offline'] == true) {
    return const FeedBlock('offline', 'You are offline on the server',
        'Reconnecting… If this stays, go offline and online again.');
  }
  if (res['busy'] == true) {
    return const FeedBlock('busy', 'You have a trip',
        'New requests come once your current or upcoming trip is done.');
  }
  return null;
}

/// The latest reason the feed is blocked, for the home banner. Cleared when
/// the feed answers normally or the driver goes offline.
final feedBlock = ValueNotifier<FeedBlock?>(null);
