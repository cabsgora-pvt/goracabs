// Ride requests whose countdown ran out on this phone.
//
// A countdown reaching zero is NOT a rejection. It used to call the reject
// endpoint, which adds the driver to the ride's rejectedBy — so a request that
// merely timed out (often while the app was in the background) could never be
// shown to that driver again. The server's own offer expiry already moves the
// offer on (lib/dispatch.ts sweepExpiredOffers), so a timeout only needs to
// take the card off screen.
//
// Taking it off screen is not enough on its own, though: the home poller and
// the requests page both re-read /rides/driver/pending every few seconds, and
// a lapsed offer can still be in that feed (open pool, or the 5s sweep lease),
// so the same card would pop straight back up in a loop. This keeps a short,
// in-memory ignore list shared by both. An entry lapses after [ttl], or earlier
// when the server makes this driver a genuinely NEW offer for the ride (it is
// offeredToMe again with a different, still-open offer window).
class DismissedRequests {
  DismissedRequests._();

  /// How long a timed-out request stays hidden from this driver.
  static const Duration ttl = Duration(seconds: 45);

  /// A re-offer must have at least this long left to count as a fresh offer.
  /// sweepExpiredOffers briefly leases a lapsed offer for 5s while it picks the
  /// next driver; that lease is not a new offer and must not resurface the card.
  static const Duration minFreshOffer = Duration(seconds: 6);

  static final Map<String, _Entry> _entries = {};

  /// Clock hook for tests.
  static DateTime Function() now = DateTime.now;

  /// Hide [id] locally after its countdown ran out. [offerExpiresAt] is the
  /// offer window the card was counting down to (null for open-pool requests).
  static void dismiss(String id, {DateTime? offerExpiresAt}) {
    if (id.isEmpty) return;
    _entries[id] = _Entry(now().add(ttl), offerExpiresAt);
  }

  /// True while [id] should stay hidden from this driver.
  static bool isSuppressed(String id, {bool offeredToMe = false, DateTime? offerExpiresAt}) {
    _prune();
    final e = _entries[id];
    if (e == null) return false;
    final freshOffer = offeredToMe &&
        offerExpiresAt != null &&
        offerExpiresAt != e.offerExpiresAt &&
        offerExpiresAt.difference(now()) > minFreshOffer;
    if (freshOffer) {
      _entries.remove(id);
      return false;
    }
    return true;
  }

  /// [isSuppressed] for a raw /rides/driver/pending row.
  static bool isSuppressedJson(Map r) => isSuppressed(
        (r['id'] ?? '').toString(),
        offeredToMe: r['offeredToMe'] == true,
        offerExpiresAt: DateTime.tryParse((r['offerExpiresAt'] ?? '').toString())?.toLocal(),
      );

  static void clear() => _entries.clear();

  static void _prune() {
    final t = now();
    _entries.removeWhere((_, e) => !e.until.isAfter(t));
  }
}

class _Entry {
  final DateTime until;
  final DateTime? offerExpiresAt;
  const _Entry(this.until, this.offerExpiresAt);
}
