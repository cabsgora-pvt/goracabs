import 'package:flutter_test/flutter_test.dart';

import 'package:gora_driver/features/ride/logic/dismissed_requests.dart';

// A countdown running out only hides a request on this phone (no server-side
// reject). It must not pop straight back up on the next poll, but must come
// back once the server genuinely offers it again or the ignore window lapses.
void main() {
  late DateTime t;
  setUp(() {
    t = DateTime(2026, 10, 15, 12, 0, 0);
    DismissedRequests.now = () => t;
    DismissedRequests.clear();
  });
  tearDown(() {
    DismissedRequests.now = DateTime.now;
    DismissedRequests.clear();
  });

  test('a timed-out request stays hidden on the next polls', () {
    final offer = t.subtract(const Duration(seconds: 1));
    DismissedRequests.dismiss('r1', offerExpiresAt: offer);
    expect(DismissedRequests.isSuppressed('r1', offeredToMe: true, offerExpiresAt: offer), isTrue);
    t = t.add(const Duration(seconds: 4));
    expect(DismissedRequests.isSuppressed('r1'), isTrue, reason: 'open pool after the offer lapsed');
    expect(DismissedRequests.isSuppressed('other'), isFalse);
  });

  test('the 5s sweep lease on the same offer does not resurface it', () {
    DismissedRequests.dismiss('r1', offerExpiresAt: t);
    final lease = t.add(const Duration(seconds: 5));
    expect(DismissedRequests.isSuppressed('r1', offeredToMe: true, offerExpiresAt: lease), isTrue);
  });

  test('a genuine re-offer to this driver shows again', () {
    DismissedRequests.dismiss('r1', offerExpiresAt: t);
    t = t.add(const Duration(seconds: 40));
    final fresh = t.add(const Duration(seconds: 20));
    expect(DismissedRequests.isSuppressed('r1', offeredToMe: true, offerExpiresAt: fresh), isFalse);
    // and the entry is gone, so it stays visible on later polls
    expect(DismissedRequests.isSuppressed('r1'), isFalse);
  });

  test('a fresh offer to someone else does not count as a re-offer', () {
    DismissedRequests.dismiss('r1');
    final fresh = t.add(const Duration(seconds: 20));
    expect(DismissedRequests.isSuppressed('r1', offeredToMe: false, offerExpiresAt: fresh), isTrue);
  });

  test('the ignore window lapses, so the ride can be shown later', () {
    DismissedRequests.dismiss('r1');
    t = t.add(DismissedRequests.ttl).add(const Duration(seconds: 1));
    expect(DismissedRequests.isSuppressed('r1'), isFalse);
  });

  test('isSuppressedJson reads a raw /rides/driver/pending row', () {
    final offer = t.toUtc();
    DismissedRequests.dismiss('r1', offerExpiresAt: offer.toLocal());
    expect(DismissedRequests.isSuppressedJson({'id': 'r1', 'offeredToMe': true, 'offerExpiresAt': offer.toIso8601String()}), isTrue);
    final fresh = t.add(const Duration(seconds: 20)).toUtc().toIso8601String();
    expect(DismissedRequests.isSuppressedJson({'id': 'r1', 'offeredToMe': true, 'offerExpiresAt': fresh}), isFalse);
  });
}
