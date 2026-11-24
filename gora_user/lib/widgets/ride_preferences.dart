import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'ride_ui/ride_ui.dart';

/// One admin-defined ride preference ("Pet friendly", "Extra luggage" ...).
class RidePreference {
  final String key;
  final String name;
  final String description;
  final String icon;
  final List<String> services;
  const RidePreference({
    required this.key,
    required this.name,
    this.description = '',
    this.icon = 'star',
    this.services = const [],
  });

  factory RidePreference.fromJson(Map<String, dynamic> j) => RidePreference(
        key: (j['key'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        description: (j['description'] ?? '').toString(),
        icon: (j['icon'] ?? 'star').toString(),
        services: ((j['services'] as List?) ?? const []).map((e) => e.toString()).toList(),
      );

  /// An empty services list means "every service", as the server treats it.
  bool appliesTo(String service) => services.isEmpty || services.contains(service);
}

/// The active preferences that apply to [service] (taxi, rental, outstation,
/// delivery, hire_driver). Never throws: a failed load is an empty list, and the
/// booking screens then hide the section.
Future<List<RidePreference>> loadRidePreferences(String service) async {
  try {
    final res = await ApiService.getRidePreferences();
    final list = (res['preferences'] as List?) ?? const [];
    return list
        .whereType<Map>()
        .map((m) => RidePreference.fromJson(Map<String, dynamic>.from(m)))
        .where((p) => p.key.isNotEmpty && p.name.isNotEmpty && p.appliesTo(service))
        .toList();
  } catch (_) {
    return const [];
  }
}

/// Material icon for an admin-chosen icon name; unknown names get a star.
IconData ridePreferenceIcon(String name) {
  switch (name.trim().toLowerCase()) {
    case 'pets':
    case 'pet':
      return Icons.pets_rounded;
    case 'luggage':
      return Icons.luggage_rounded;
    case 'accessible':
    case 'wheelchair':
      return Icons.accessible_rounded;
    case 'ac_unit':
    case 'ac':
      return Icons.ac_unit_rounded;
    case 'smoke_free':
      return Icons.smoke_free_rounded;
    case 'child_care':
    case 'child':
      return Icons.child_care_rounded;
    case 'music_note':
    case 'music':
      return Icons.music_note_rounded;
    default:
      return Icons.star_rounded;
  }
}

/// Multi-select chips for the ride preferences. Renders nothing when
/// [preferences] is empty, so callers can drop it in unconditionally.
class RidePreferenceChips extends StatelessWidget {
  final List<RidePreference> preferences;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  /// Shows the "Ride preferences" heading above the chips.
  final bool showTitle;
  const RidePreferenceChips({
    super.key,
    required this.preferences,
    required this.selected,
    required this.onChanged,
    this.showTitle = true,
  });

  @override
  Widget build(BuildContext context) {
    if (preferences.isEmpty) return const SizedBox.shrink();
    final picked = preferences.where((p) => selected.contains(p.key) && p.description.isNotEmpty).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      if (showTitle) ...[
        Text('Ride preferences', style: RideUi.body(context, size: 15, weight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text('Tell your driver what you need', style: RideUi.caption(context, size: 12.5)),
        const SizedBox(height: 10),
      ],
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final p in preferences)
            _PrefChip(
              pref: p,
              selected: selected.contains(p.key),
              onTap: () {
                final next = {...selected};
                if (!next.remove(p.key)) next.add(p.key);
                onChanged(next);
              },
            ),
        ],
      ),
      for (final p in picked)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
          child: Text('${p.name}: ${p.description}', style: RideUi.caption(context, size: 11.5)),
        ),
    ]);
  }
}

class _PrefChip extends StatelessWidget {
  final RidePreference pref;
  final bool selected;
  final VoidCallback onTap;
  const _PrefChip({required this.pref, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : RideUi.ink(context);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? RideUi.navy : RideUi.tile(context),
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(selected ? Icons.check_rounded : ridePreferenceIcon(pref.icon), size: 16, color: fg),
              const SizedBox(width: 6),
              Flexible(
                child: Text(pref.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
