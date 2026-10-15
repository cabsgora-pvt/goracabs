// ─────────────────────────────────────────────────────────────────────────────
// Short place names for route labels.
// ─────────────────────────────────────────────────────────────────────────────

const _states = {
  'andhra pradesh', 'arunachal pradesh', 'assam', 'bihar', 'chhattisgarh', 'goa',
  'gujarat', 'haryana', 'himachal pradesh', 'jharkhand', 'karnataka', 'kerala',
  'madhya pradesh', 'maharashtra', 'manipur', 'meghalaya', 'mizoram', 'nagaland',
  'odisha', 'punjab', 'rajasthan', 'sikkim', 'tamil nadu', 'telangana', 'tripura',
  'uttar pradesh', 'uttarakhand', 'west bengal',
  'andaman and nicobar islands', 'chandigarh', 'dadra and nagar haveli and daman and diu',
  'delhi', 'jammu and kashmir', 'ladakh', 'lakshadweep', 'puducherry',
};

final _pin = RegExp(r'\s*\b\d{6}\b\s*');

/// The town or city in a place address — "DLF Cyber City, Sector 24,
/// Gurugram, Haryana 122002" is Gurugram.
///
/// Outstation trips stored the picked address itself as the "city", so the
/// one-line "From → To" label on the ride screens read "DLF Cyber City, Sector
/// 24, Gurugra…" and never reached the destination. Addresses end "…, Town,
/// State PIN, India": the country, the PIN and the state are dropped, and the
/// last part left is the town. An address with nothing to drop is returned as
/// it is, so a name that is already short stays that way.
String cityOf(String address) {
  final parts = address.split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
  bool droppable(String part) {
    final p = part.replaceAll(_pin, ' ').trim().toLowerCase();
    return p.isEmpty || p == 'india' || _states.contains(p);
  }
  while (parts.length > 1 && droppable(parts.last)) {
    parts.removeLast();
  }
  if (parts.isEmpty) return address.trim();
  final town = parts.last.replaceAll(_pin, ' ').trim();
  return town.isEmpty ? address.trim() : town;
}
