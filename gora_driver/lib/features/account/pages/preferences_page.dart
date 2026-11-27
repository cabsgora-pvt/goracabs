import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../services/driver_api_service.dart';
import '../../../widgets/captain_ui/captain_ui.dart';
import '../service_prefs.dart';

/// Trip preferences, full page: a two-per-row grid of services (big image,
/// name, a blue check on the ones this driver takes), the admin-defined ride
/// preferences, for a higher tier (Prime SUV) a switch to also take its
/// category's lower-tier rides (Cab, Prime Sedan), and a sticky Save. Saved
/// with POST /auth/driver/preferences.
class PreferencesPage extends StatefulWidget {
  static const route = '/preferences';
  const PreferencesPage({super.key});
  @override
  State<PreferencesPage> createState() => _PreferencesPageState();
}

class _PreferencesPageState extends State<PreferencesPage> {
  // Service opt-ins
  bool _rental = false, _outstation = false, _hireDriver = false, _delivery = false;
  // Admin allow-gates (a disallowed service is shown greyed out, not pickable)
  bool _allowTaxi = true, _allowRental = true, _allowOutstation = true, _allowHireDriver = true, _allowDelivery = true;
  bool _loading = true, _saving = false;
  // Admin-defined ride preferences and the ones this driver offers
  List<RidePrefDef> _prefDefs = const [];
  Set<String> _ridePrefs = {};
  // A higher tier (Prime SUV) may also take rides booked for the lower tiers
  // of its category (profile lowerTiers: ["Cab", "Prime Sedan"]). The switch
  // shows only when there are some.
  List<String> _lowerTiers = const [];
  bool _acceptLowerTiers = false;
  // What the server last confirmed, to tell "saved" from "unsaved changes".
  String _savedSig = '';

  String get _sig => [
        _rental, _outstation, _hireDriver, _delivery, (_ridePrefs.toList()..sort()).join(','),
        _lowerTiers.isNotEmpty && _acceptLowerTiers,
      ].join('|');
  bool get _dirty => !_loading && _sig != _savedSig;

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  Future<void> _loadCurrent() async {
    final defs = loadRidePrefDefs();
    try {
      final res = await DriverApiService.getProfile();
      // Accept both shapes: { driver: {...} } or the driver object directly.
      final d = (res['driver'] ?? res) as Map?;
      if (d != null && mounted) {
        setState(() {
          _ridePrefs = ridePrefKeysOf(d['ridePreferences']);
          _outstation = d['acceptsOutstation'] == true;
          _rental = d['acceptsRental'] == true;
          _hireDriver = d['acceptsHireDriver'] == true;
          _delivery = d['acceptsDelivery'] == true;
          _allowTaxi = d['allowTaxi'] != false;
          _allowRental = d['allowRental'] != false;
          _allowOutstation = d['allowOutstation'] != false;
          _allowHireDriver = d['allowHireDriver'] != false;
          _allowDelivery = d['allowDelivery'] != false;
          _lowerTiers = lowerTierNames(d['lowerTiers']);
          _acceptLowerTiers = d['acceptLowerTiers'] == true;
        });
      }
    } catch (_) {}
    final loadedDefs = await defs;
    // Always clear the loader — never leave the page stuck on the spinner.
    if (mounted) {
      setState(() {
        _prefDefs = loadedDefs;
        _loading = false;
        _savedSig = _sig;
      });
    }
  }

  Future<void> _savePrefs() async {
    setState(() => _saving = true);
    try {
      final res = await DriverApiService.updatePreferences({
        'acceptsOutstation': _outstation,
        'acceptsRental': _rental,
        'acceptsHireDriver': _hireDriver,
        'acceptsDelivery': _delivery,
        // Only sent once the list loaded, so a failed load never clears them.
        if (_prefDefs.isNotEmpty) 'ridePreferences': _ridePrefs.toList(),
        // Only when the switch is on screen.
        if (_lowerTiers.isNotEmpty) 'acceptLowerTiers': _acceptLowerTiers,
      });
      if (!mounted) return;
      if (res['error'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: ${res['error']}'), backgroundColor: AppColors.red));
        return;
      }
      final prefs = res['preferences'] as Map<String, dynamic>?;
      setState(() {
        _outstation = (prefs?['acceptsOutstation'] as bool?) ?? _outstation;
        _rental = (prefs?['acceptsRental'] as bool?) ?? _rental;
        _hireDriver = (prefs?['acceptsHireDriver'] as bool?) ?? _hireDriver;
        _delivery = (prefs?['acceptsDelivery'] as bool?) ?? _delivery;
        if (prefs?['ridePreferences'] is List) _ridePrefs = ridePrefKeysOf(prefs?['ridePreferences']);
        if (prefs?['lowerTiers'] is List) _lowerTiers = lowerTierNames(prefs?['lowerTiers']);
        _acceptLowerTiers = (prefs?['acceptLowerTiers'] as bool?) ?? _acceptLowerTiers;
        _savedSig = _sig;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preferences saved'), backgroundColor: AppColors.green));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Network error: $e'), backgroundColor: AppColors.red));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _valueOf(String key) =>
      key == 'rental' ? _rental : key == 'outstation' ? _outstation : key == 'hire_driver' ? _hireDriver : _delivery;
  bool _allowOf(String key) =>
      key == 'rental' ? _allowRental : key == 'outstation' ? _allowOutstation : key == 'hire_driver' ? _allowHireDriver : _allowDelivery;
  void _setValue(String key, bool v) => setState(() {
        if (key == 'rental') {
          _rental = v;
        } else if (key == 'outstation') {
          _outstation = v;
        } else if (key == 'hire_driver') {
          _hireDriver = v;
        } else {
          _delivery = v;
        }
      });

  @override
  Widget build(BuildContext context) {
    final picked = kServiceDefs.where((s) => _allowOf(s.key) && _valueOf(s.key)).length + (_allowTaxi ? 1 : 0);
    return Scaffold(
      appBar: blueAppBar('Trip preferences'),
      backgroundColor: Cap.bg,
      body: _loading
          ? const AppLoader()
          : CustomScrollView(slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                sliver: SliverToBoxAdapter(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('SERVICES', style: Cap.caption(size: 11).copyWith(fontWeight: FontWeight.w800, letterSpacing: 1.6)),
                    const SizedBox(height: 4),
                    Text('Choose the trips you want', style: Cap.title(size: 24)),
                    const SizedBox(height: 4),
                    Text('Tap a card to turn it on or off · $picked selected',
                        key: const ValueKey('prefs_selected_count'), style: Cap.caption(size: 13)),
                    const SizedBox(height: 14),
                  ]),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.82),
                  delegate: SliverChildListDelegate([
                    ServiceGridCard(
                      key: const ValueKey('svc_card_taxi'),
                      title: 'Taxi / Cab',
                      sub: 'Always on',
                      image: kTaxiImage,
                      selected: _allowTaxi,
                      allowed: _allowTaxi,
                      alwaysOn: true,
                    ),
                    for (final s in kServiceDefs)
                      ServiceGridCard(
                        key: ValueKey('svc_card_${s.key}'),
                        title: s.title,
                        sub: s.sub,
                        image: s.image,
                        selected: _allowOf(s.key) && _valueOf(s.key),
                        allowed: _allowOf(s.key),
                        onTap: _saving || !_allowOf(s.key) ? null : () => _setValue(s.key, !_valueOf(s.key)),
                      ),
                  ]),
                ),
              ),
              if (_lowerTiers.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: LowerTiersCard(
                      tiers: _lowerTiers,
                      value: _acceptLowerTiers,
                      onChanged: _saving ? null : (v) => setState(() => _acceptLowerTiers = v),
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                sliver: SliverToBoxAdapter(
                  child: RidePrefsSection(
                    defs: _prefDefs,
                    selected: _ridePrefs,
                    onChanged: (key, on) => setState(() => on ? _ridePrefs.add(key) : _ridePrefs.remove(key)),
                  ),
                ),
              ),
            ]),
      // Sticky: always reachable however long the list gets.
      bottomNavigationBar: _loading
          ? null
          : SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: BoxDecoration(
                  color: Cap.surface,
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 14, offset: const Offset(0, -4))],
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(_dirty ? Icons.edit_note_rounded : Icons.cloud_done_rounded,
                        size: 16, color: _dirty ? AppColors.orange : AppColors.green),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(_dirty ? 'You have unsaved changes' : 'All changes saved',
                          key: const ValueKey('prefs_save_state'),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: Cap.caption(size: 12.5, color: _dirty ? AppColors.orange : AppColors.green)
                              .copyWith(fontWeight: FontWeight.w700)),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  PrimaryButton(
                    label: _saving ? 'Saving...' : 'Save Preferences',
                    onTap: _saving ? null : _savePrefs,
                  ),
                ]),
              ),
            ),
    );
  }
}

/// The lower tiers from the profile / preferences reply (["Cab", "Prime
/// Sedan"]), blanks dropped.
List<String> lowerTierNames(Object? raw) => raw is List
    ? raw.map((e) => '$e'.trim()).where((e) => e.isNotEmpty).toList()
    : const [];

/// "Also take Cab, Prime Sedan rides".
String lowerTiersTitle(List<String> tiers) => 'Also take ${tiers.join(', ')} rides';

const lowerTiersSubtitle = "More trips when it's busy. You earn the fare of the ride the rider booked.";

/// A higher-tier driver's opt-in to rides booked for the lower tiers of the
/// same category: a card with a blue switch.
class LowerTiersCard extends StatelessWidget {
  final List<String> tiers;
  final bool value;
  final ValueChanged<bool>? onChanged;
  const LowerTiersCard({super.key, required this.tiers, required this.value, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('prefs_lower_tiers'),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: Cap.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: value ? AppColors.primary : Cap.divider, width: value ? 2 : 1),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.10), shape: BoxShape.circle),
          child: const Icon(Icons.layers_rounded, color: AppColors.primary, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(lowerTiersTitle(tiers), style: Cap.body(size: 15, weight: FontWeight.w900)),
            const SizedBox(height: 3),
            Text(lowerTiersSubtitle, style: Cap.caption(size: 12.5)),
          ]),
        ),
        const SizedBox(width: 6),
        Switch(
          key: const ValueKey('prefs_lower_tiers_switch'),
          value: value,
          onChanged: onChanged,
          activeTrackColor: AppColors.primary,
        ),
      ]),
    );
  }
}

/// One service in the preferences grid: a big image, the name, and a blue
/// check when the driver takes these trips. A service the admin has not
/// enabled for this driver is greyed out and cannot be picked.
class ServiceGridCard extends StatelessWidget {
  final String title, sub, image;
  final bool selected, allowed, alwaysOn;
  final VoidCallback? onTap;
  const ServiceGridCard({
    super.key,
    required this.title,
    required this.sub,
    required this.image,
    required this.selected,
    required this.allowed,
    this.alwaysOn = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final on = allowed && selected;
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: Cap.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: on ? AppColors.primary : Cap.divider, width: on ? 2 : 1),
        boxShadow: [
          BoxShadow(
              color: (on ? AppColors.primary : Colors.black).withValues(alpha: on ? 0.16 : 0.05),
              blurRadius: on ? 16 : 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Stack(children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: (on ? AppColors.primary : Cap.muted).withValues(alpha: on ? 0.08 : 0.06),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Image.asset(image,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Center(
                              child: Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
                                child: const Icon(Icons.local_taxi_rounded, size: 34, color: AppColors.primary),
                              ),
                            )),
                  ),
                ),
                const SizedBox(height: 10),
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Cap.body(size: 15, weight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(allowed ? sub : 'Not enabled by admin',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Cap.caption(size: 11.5, color: allowed ? null : AppColors.red)),
              ]),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: Container(
                decoration: BoxDecoration(color: Cap.surface, shape: BoxShape.circle),
                child: Icon(
                  !allowed
                      ? Icons.lock_rounded
                      : on
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                  size: 26,
                  color: !allowed
                      ? Cap.muted
                      : on
                          ? AppColors.primary
                          : Cap.divider,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
    return Semantics(
      button: onTap != null,
      selected: on,
      enabled: allowed,
      label: '$title${alwaysOn ? ', always on' : ''}${allowed ? '' : ', not enabled by admin'}',
      child: Opacity(opacity: allowed ? 1 : 0.5, child: card),
    );
  }
}
