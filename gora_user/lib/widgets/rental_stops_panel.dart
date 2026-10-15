import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

/// Destinations a rider adds while a rental is under way.
///
/// A rental has no fixed drop: the rider tells the driver where to go next as
/// the day goes on. This lived in the rental booking screen's sheet; it moved
/// here with the rest of rental tracking so it was not lost in the move.
///
/// The list is always the server's (`rentalStops` on the polled ride), so what
/// the rider sees is what the driver was sent. [onAdded] asks the ride screen to
/// poll straight away rather than waiting up to 3s for the new stop to appear.
class RentalStopsPanel extends StatefulWidget {
  final String rideId;
  final Map<String, dynamic> ride;
  final VoidCallback onAdded;
  const RentalStopsPanel({
    super.key,
    required this.rideId,
    required this.ride,
    required this.onAdded,
  });

  @override
  State<RentalStopsPanel> createState() => _RentalStopsPanelState();
}

class _RentalStopsPanelState extends State<RentalStopsPanel> {
  bool _adding = false;

  List<Map<String, dynamic>> get _stops =>
      ((widget.ride['rentalStops'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  Future<void> _add(String address, double lat, double lng) async {
    setState(() => _adding = true);
    final messenger = ScaffoldMessenger.of(context);
    final res = await ApiService.rentalAction(
        widget.rideId, {'action': 'addStop', 'address': address, 'lat': lat, 'lng': lng});
    if (!mounted) return;
    setState(() => _adding = false);
    // The booking screen's version reported success whatever the server said:
    // post() never throws, so a 401 or 400 still showed "driver notified".
    final error = res['error'];
    messenger.showSnackBar(SnackBar(
      content: Text(error == null ? 'Destination added — driver notified' : 'Could not add destination: $error'),
      backgroundColor: error == null ? Colors.green : Colors.red,
    ));
    if (error == null) widget.onAdded();
  }

  void _openSearch() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // cardColor, not white: in dark mode the search text was white on white.
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _PlaceSearchSheet(onPicked: _add),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stops = _stops;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.route, size: 18, color: AppTheme.primaryBlue),
          const SizedBox(width: 8),
          const Expanded(child: Text('Where to next?',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
          Text('${stops.length} added', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ]),
        for (final (i, s) in stops.indexed)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 10 : 6),
            child: Row(children: [
              CircleAvatar(
                radius: 11,
                backgroundColor: AppTheme.primaryBlue,
                child: Text('${i + 1}',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text((s['address'] ?? '').toString(),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5))),
            ]),
          ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _adding ? null : _openSearch,
            icon: _adding
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryBlue))
                : const Icon(Icons.add_location_alt_outlined, size: 18),
            label: Text(stops.isEmpty ? 'Add destination' : 'Add another destination'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryBlue,
              side: const BorderSide(color: AppTheme.primaryBlue),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Place search: type, pick a suggestion, resolve it to coordinates.
class _PlaceSearchSheet extends StatefulWidget {
  final Future<void> Function(String address, double lat, double lng) onPicked;
  const _PlaceSearchSheet({required this.onPicked});

  @override
  State<_PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends State<_PlaceSearchSheet> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _suggestions = const [];
  // The query a result belongs to, so a slow answer for "Ahm" cannot replace
  // the suggestions already showing for "Ahmedabad airport".
  String _latestQuery = '';

  @override
  void dispose() {
    // The booking screen's version leaked both: the controller was never
    // disposed and a pending debounce fired into a closed sheet.
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _latestQuery = q;
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (q.trim().length < 2) {
        if (mounted) setState(() => _suggestions = const []);
        return;
      }
      final r = await ApiService.placesAutocomplete(q);
      if (mounted && q == _latestQuery) setState(() => _suggestions = r);
    });
  }

  Future<void> _pick(Map<String, dynamic> s) async {
    final details = await ApiService.placeDetails((s['placeId'] ?? '').toString());
    if (!mounted) return;
    if (details == null || details['lat'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not find that place. Try another.')));
      return;
    }
    Navigator.pop(context);
    await widget.onPicked(
      (details['address'] ?? s['description'] ?? '').toString(),
      (details['lat'] as num).toDouble(),
      (details['lng'] as num).toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Add destination', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text('Your driver will be notified of the new stop',
        style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      const SizedBox(height: 14),
      TextField(
        controller: _ctrl,
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'Search a place',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onChanged: _onChanged,
      ),
      const SizedBox(height: 8),
      for (final s in _suggestions.take(6))
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.location_on_outlined, color: AppTheme.primaryBlue),
          title: Text((s['description'] ?? '').toString(),
            maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
          onTap: () => _pick(s),
        ),
      const SizedBox(height: 8),
    ]),
  );
}
