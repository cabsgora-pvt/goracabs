import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// "Looking for a driver" full-screen view: map with pickup → drop route, the trip
// summary (addresses + fare) and a Cancel button. No spinner, no car icons.
// Reusable across every service. Parent keeps polling and pops this on accept;
// [onCancel] runs the parent's cancel-with-reason flow.
class FindingDriverView extends StatefulWidget {
  final double pickupLat, pickupLng;
  final double? dropLat, dropLng;
  final String pickupAddress, dropAddress;
  final String? fareText;       // e.g. "₹540"
  final String serviceLabel;
  final IconData serviceIcon;
  final int? etaMin;
  final VoidCallback onCancel;
  const FindingDriverView({
    super.key,
    required this.pickupLat,
    required this.pickupLng,
    required this.serviceLabel,
    required this.serviceIcon,
    required this.onCancel,
    this.dropLat,
    this.dropLng,
    this.pickupAddress = '',
    this.dropAddress = '',
    this.fareText,
    this.etaMin,
  });

  @override
  State<FindingDriverView> createState() => _FindingDriverViewState();
}

class _FindingDriverViewState extends State<FindingDriverView> {
  static const Color _navy = Color(0xFF1C2656);
  GoogleMapController? _ctrl;

  void _fitBounds() {
    if (_ctrl == null || widget.dropLat == null) return;
    final sw = LatLng(
      widget.pickupLat < widget.dropLat! ? widget.pickupLat : widget.dropLat!,
      widget.pickupLng < widget.dropLng! ? widget.pickupLng : widget.dropLng!,
    );
    final ne = LatLng(
      widget.pickupLat > widget.dropLat! ? widget.pickupLat : widget.dropLat!,
      widget.pickupLng > widget.dropLng! ? widget.pickupLng : widget.dropLng!,
    );
    _ctrl!.animateCamera(CameraUpdate.newLatLngBounds(LatLngBounds(southwest: sw, northeast: ne), 70));
  }

  @override
  Widget build(BuildContext context) {
    final hasDrop = widget.dropLat != null && widget.dropLng != null;
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(child: GoogleMap(
          initialCameraPosition: CameraPosition(target: LatLng(widget.pickupLat, widget.pickupLng), zoom: 14),
          onMapCreated: (c) { _ctrl = c; _fitBounds(); },
          zoomControlsEnabled: false,
          myLocationButtonEnabled: false,
          markers: {
            Marker(markerId: const MarkerId('p'), position: LatLng(widget.pickupLat, widget.pickupLng),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)),
            if (hasDrop) Marker(markerId: const MarkerId('d'), position: LatLng(widget.dropLat!, widget.dropLng!),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed)),
          },
          polylines: hasDrop ? {
            Polyline(polylineId: const PolylineId('r'), color: _navy, width: 4,
              points: [LatLng(widget.pickupLat, widget.pickupLng), LatLng(widget.dropLat!, widget.dropLng!)]),
          } : {},
        )),
        // Service chip (top)
        Positioned(top: 0, left: 0, right: 0, child: SafeArea(child: Padding(
          padding: const EdgeInsets.all(12),
          child: Align(alignment: Alignment.centerLeft, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 6)]),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(widget.serviceIcon, size: 16, color: _navy),
              const SizedBox(width: 8),
              Text(widget.serviceLabel, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            ]),
          )),
        ))),
        // Bottom trip card
        Positioned(left: 0, right: 0, bottom: 0, child: Container(
          decoration: BoxDecoration(color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 16, offset: const Offset(0, -4))]),
          child: SafeArea(top: false, child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Heading + thin progress bar (no spinner)
              Row(children: [
                Expanded(child: Text('Looking for a driver', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900))),
                if (widget.etaMin != null) Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: _navy.withOpacity(0.08), borderRadius: BorderRadius.circular(20)),
                  child: Text('~${widget.etaMin} min', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _navy))),
              ]),
              const SizedBox(height: 4),
              Text('Connecting you with nearby drivers', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              const SizedBox(height: 12),
              ClipRRect(borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(minHeight: 4, backgroundColor: _navy.withOpacity(0.10), valueColor: const AlwaysStoppedAnimation(_navy))),
              const SizedBox(height: 16),
              // Route: pickup → drop
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.grey.withOpacity(0.06), borderRadius: BorderRadius.circular(12)),
                child: Column(children: [
                  Row(children: [
                    const Icon(Icons.radio_button_checked, size: 15, color: Color(0xFF4CAF50)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(widget.pickupAddress.isEmpty ? 'Pickup' : widget.pickupAddress,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                  ]),
                  if (widget.dropAddress.isNotEmpty) ...[
                    Padding(padding: const EdgeInsets.only(left: 6), child: Align(alignment: Alignment.centerLeft,
                      child: Container(width: 2, height: 16, color: Colors.grey[300]))),
                    Row(children: [
                      const Icon(Icons.location_on, size: 15, color: Color(0xFFFF5252)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(widget.dropAddress, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                    ]),
                  ],
                ]),
              ),
              if (widget.fareText != null) ...[
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Estimated fare', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  Text(widget.fareText!, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _navy)),
                ]),
              ],
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: OutlinedButton.icon(
                onPressed: widget.onCancel,
                icon: const Icon(Icons.close, size: 18, color: Colors.red),
                label: const Text('Cancel Ride', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w800, fontSize: 15)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red), padding: const EdgeInsets.symmetric(vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              )),
            ]),
          )),
        )),
      ]),
    );
  }
}
