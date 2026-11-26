import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/api_service.dart';
import 'ride_ui/ride_ui.dart';

/// One popular place from GET /api/places/popular.
class PopularPlace {
  final String id, name, category, type, address;
  final double lat, lng;
  final double? rating, distanceKm;
  final String? photoUrl;
  const PopularPlace({
    required this.id, required this.name, required this.category, required this.type,
    required this.address, required this.lat, required this.lng,
    this.rating, this.distanceKm, this.photoUrl,
  });

  static PopularPlace? fromJson(Map<String, dynamic> j) {
    final lat = (j['lat'] as num?)?.toDouble(), lng = (j['lng'] as num?)?.toDouble();
    final name = (j['name'] ?? '').toString().trim();
    if (lat == null || lng == null || name.isEmpty) return null;
    final photo = (j['photoUrl'] ?? '').toString();
    return PopularPlace(
      id: (j['id'] ?? name).toString(),
      name: name,
      category: (j['category'] ?? '').toString(),
      type: (j['type'] ?? '').toString(),
      address: (j['address'] ?? '').toString(),
      lat: lat,
      lng: lng,
      rating: (j['rating'] as num?)?.toDouble(),
      distanceKm: (j['distanceKm'] as num?)?.toDouble(),
      photoUrl: photo.startsWith('https://') ? photo : null,
    );
  }

  /// The drop label booking shows: "Mehrangarh Fort, Fort Road, Jodhpur".
  String get dropLabel => address.isEmpty ? name : '$name, $address';
}

IconData iconForPlaceType(String type) => switch (type) {
      'train_station' => Icons.train_rounded,
      'airport' => Icons.flight_rounded,
      'bus_station' => Icons.directions_bus_rounded,
      'shopping_mall' => Icons.local_mall_rounded,
      _ => Icons.account_balance_rounded,
    };

/// "Popular places near you" — stations, airport, bus stand, malls and tourist
/// spots around the rider, with photos; tapping one books a ride there.
/// Hidden when there is nothing to show (no location yet, no places, offline).
class PopularPlacesSection extends StatefulWidget {
  final LatLng? at;
  final void Function(PopularPlace place) onTap;
  const PopularPlacesSection({super.key, required this.at, required this.onTap});

  @override
  State<PopularPlacesSection> createState() => _PopularPlacesSectionState();
}

class _PopularPlacesSectionState extends State<PopularPlacesSection> {
  List<PopularPlace> _places = const [];
  bool _loading = false;
  LatLng? _loadedFor;

  @override
  void initState() {
    super.initState();
    _maybeLoad();
  }

  @override
  void didUpdateWidget(covariant PopularPlacesSection old) {
    super.didUpdateWidget(old);
    _maybeLoad();
  }

  // Reload only when the rider has moved more than 5 km (new city / area).
  void _maybeLoad() {
    final at = widget.at;
    if (at == null || _loading) return;
    final prev = _loadedFor;
    if (prev != null && Geolocator.distanceBetween(prev.latitude, prev.longitude, at.latitude, at.longitude) < 5000) return;
    _load(at);
  }

  Future<void> _load(LatLng at) async {
    setState(() => _loading = true);
    final list = await ApiService.getPopularPlaces(at.latitude, at.longitude);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _loadedFor = at;
      _places = list.map(PopularPlace.fromJson).whereType<PopularPlace>().toList();
    });
    // The rider's position may have moved on while this was loading (the app
    // starts from the phone's last known fix — another city — and the real one
    // arrives a moment later). Check again, or the old city's places stay.
    _maybeLoad();
  }

  @override
  Widget build(BuildContext context) {
    if (_places.isEmpty && !_loading) return const SizedBox.shrink();
    return Column(
      key: const ValueKey('popular-places'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        const RideSectionTitle('Popular places near you'),
        const SizedBox(height: 10),
        SizedBox(
          height: 186,
          child: _places.isEmpty
              ? ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: 3,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, __) => Container(
                    width: 150,
                    decoration: BoxDecoration(color: RideUi.tile(context), borderRadius: BorderRadius.circular(14)),
                  ),
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _places.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => _card(_places[i]),
                ),
        ),
      ],
    );
  }

  Widget _card(PopularPlace p) {
    final fallback = Container(
      color: RideUi.tile(context),
      alignment: Alignment.center,
      child: Icon(iconForPlaceType(p.type), size: 40, color: RideUi.muted(context)),
    );
    return Semantics(
      button: true,
      label: 'Book a ride to ${p.name}',
      child: InkWell(
        key: ValueKey('popular-${p.id}'),
        borderRadius: BorderRadius.circular(14),
        onTap: () => widget.onTap(p),
        child: Container(
          width: 150,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: RideUi.surface(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: RideUi.divider(context)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              height: 104,
              width: double.infinity,
              child: Stack(fit: StackFit.expand, children: [
                p.photoUrl == null
                    ? fallback
                    : Image.network(
                        p.photoUrl!,
                        fit: BoxFit.cover,
                        loadingBuilder: (c, child, prog) => prog == null ? child : fallback,
                        errorBuilder: (_, __, ___) => fallback,
                      ),
                Positioned(
                  left: 8, top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.62), borderRadius: BorderRadius.circular(20)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(iconForPlaceType(p.type), size: 12, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(p.category, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: RideUi.body(context, size: 13.5, weight: FontWeight.w800)),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Row(children: [
                if (p.distanceKm != null)
                  Text('${p.distanceKm! < 10 ? p.distanceKm!.toStringAsFixed(1) : p.distanceKm!.round()} km',
                      style: RideUi.caption(context, size: 12)),
                const Spacer(),
                if (p.rating != null) ...[
                  const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF5A524)),
                  Text(p.rating!.toStringAsFixed(1), style: RideUi.caption(context, size: 12)),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
