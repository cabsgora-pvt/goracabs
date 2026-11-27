// Vehicle categories and tiers for registration (Cab → Cab / Prime Sedan /
// Prime SUV), from GET /api/vehicles/types.
//
// Each type carries `category` ('bike' | 'scooter' | 'auto' | 'cab' | 'truck' |
// 'other'), `categoryLabel`, `rank` (1 = basic, higher = premium), `tagline`,
// `requirements` and `requirementsText`. An older server sends none of these:
// the category and rank are then inferred from the name exactly as the server
// does (goraadmin lib/vehicle-tiers.ts), so the page still groups sensibly.

/// Display names of the known categories (the server's CATEGORY_LABELS).
const kVehicleCategoryLabels = <String, String>{
  'bike': 'Bike', 'scooter': 'Scooter', 'auto': 'Auto', 'cab': 'Cab', 'truck': 'Truck', 'other': 'Other',
};

/// The server's inferCategory: the category a type with no `category` is in.
String inferVehicleCategory(String name) {
  final n = name.toLowerCase();
  if (RegExp(r'truck|tempo|loader|cargo|goods|pickup|\bace\b').hasMatch(n)) return 'truck';
  if (n.contains('scoot')) return 'scooter';
  if (RegExp(r'bike|moto|two.?wheel').hasMatch(n)) return 'bike';
  if (RegExp(r'auto|rick').hasMatch(n)) return 'auto';
  return 'cab';
}

/// The server's inferRank: 3 for an SUV / 7-seater, 2 for a premium sedan, 1 otherwise.
int inferVehicleRank(String name) {
  final n = name.toLowerCase();
  if (RegExp(r'suv|\bxl\b|innova|7.?seat|6.?seat').hasMatch(n)) return 3;
  if (RegExp(r'prime|premium|premier|sedan|luxury|comfort').hasMatch(n)) return 2;
  return 1;
}

String _nameOf(Map vt) => (vt['name'] ?? '').toString().trim();

/// The type's category key (lower-case), stored or inferred from its name.
String vehicleCategoryOf(Map vt) {
  final c = (vt['category'] ?? '').toString().trim().toLowerCase();
  return c.isNotEmpty ? c : inferVehicleCategory(_nameOf(vt));
}

/// The type's tier inside its category (1 = basic), stored or inferred.
int vehicleRankOf(Map vt) {
  final r = vt['rank'];
  final n = r is num ? r : num.tryParse('${r ?? ''}'.trim());
  if (n != null && n.isFinite && n >= 1) return n.round();
  return inferVehicleRank(_nameOf(vt));
}

/// "Cab", "Truck" … — the server's categoryLabel, else the known label, else
/// the key with a capital letter.
String vehicleCategoryLabelOf(Map vt) {
  final l = (vt['categoryLabel'] ?? '').toString().trim();
  if (l.isNotEmpty) return l;
  final c = vehicleCategoryOf(vt);
  return kVehicleCategoryLabels[c] ?? (c.isEmpty ? 'Other' : c[0].toUpperCase() + c.substring(1));
}

/// "2019 or newer · Dzire, Aura" — the server's requirementsText, or built
/// from `requirements` the same way when only those were sent. '' = no rules.
String vehicleRequirementsText(Map vt) {
  final t = (vt['requirementsText'] ?? '').toString().trim();
  if (t.isNotEmpty) return t;
  final q = vt['requirements'];
  if (q is! Map) return '';
  final parts = <String>[];
  final y = q['minModelYear'];
  if (y is num && y >= 1990) parts.add('${y.round()} or newer');
  final r = q['minDriverRating'];
  if (r is num && r > 0) parts.add('rating $r+');
  final models = q['allowedModels'];
  if (models is List) {
    final m = models.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList();
    if (m.isNotEmpty) parts.add(m.take(6).join(', ') + (m.length > 6 ? '…' : ''));
  }
  final note = (q['note'] ?? '').toString().trim();
  if (note.isNotEmpty) parts.add(note);
  return parts.join(' · ');
}

/// The type's one-line pitch ("Top-rated drivers, newer sedans"), '' if none.
String vehicleTaglineOf(Map vt) => (vt['tagline'] ?? '').toString().trim();

/// One category on the first registration step and the types in it, basic
/// tier first.
class VehicleCategory {
  final String key;
  final String label;
  final List<Map<String, dynamic>> types;
  const VehicleCategory({required this.key, required this.label, required this.types});

  /// The basic (rank 1, or lowest) type — its photo stands for the category.
  Map<String, dynamic> get representative => types.first;
  int get count => types.length;
  bool get isSingle => types.length == 1;

  /// "1 option" / "3 options".
  String get countText => count == 1 ? '1 option' : '$count options';

  bool contains(Map<String, dynamic>? vt) => vt != null && types.any((t) => sameVehicleType(t, vt));
}

/// The id a type is known by (`_id`, or `id`), '' if neither.
String vehicleTypeIdOf(Map? vt) => (vt?['_id'] ?? vt?['id'] ?? '').toString();

bool sameVehicleType(Map? a, Map? b) {
  final x = vehicleTypeIdOf(a);
  return x.isNotEmpty && x == vehicleTypeIdOf(b);
}

/// Groups [types] by category. Categories keep the order the server listed
/// their first type in (its sortOrder); inside one, types are sorted by rank,
/// ties keeping server order.
List<VehicleCategory> groupVehicleTypes(List<Map<String, dynamic>> types) {
  final byKey = <String, List<(int, Map<String, dynamic>)>>{};
  final labels = <String, String>{};
  for (final (i, vt) in types.indexed) {
    final key = vehicleCategoryOf(vt);
    byKey.putIfAbsent(key, () => []).add((i, vt));
    labels.putIfAbsent(key, () => vehicleCategoryLabelOf(vt));
  }
  return [
    for (final e in byKey.entries)
      VehicleCategory(
        key: e.key,
        label: labels[e.key]!,
        types: (e.value.toList()
              ..sort((a, b) {
                final r = vehicleRankOf(a.$2).compareTo(vehicleRankOf(b.$2));
                return r != 0 ? r : a.$1.compareTo(b.$1);
              }))
            .map((p) => p.$2)
            .toList(),
      ),
  ];
}

/// The oldest model year the picker offers.
const kOldestModelYear = 1995;

/// Model years for the picker, newest first: next year down to [kOldestModelYear].
List<int> modelYearOptions({DateTime? now}) {
  final top = (now ?? DateTime.now()).year + 1;
  return [for (var y = top; y >= kOldestModelYear; y--) y];
}
