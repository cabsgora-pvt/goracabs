import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/models.dart';
import '../bloc/ride_bloc.dart';
import 'on_ride_page.dart';

class IncomingRidePage extends StatefulWidget {
  static const route = '/incoming-ride';
  const IncomingRidePage({super.key});
  @override State<IncomingRidePage> createState() => _IncomingRidePageState();
}

class _IncomingRidePageState extends State<IncomingRidePage> {
  int _timer = 20;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_timer > 0) setState(() => _timer--);
      else { _t?.cancel(); if (mounted) Navigator.pop(context); }
    });
  }

  @override
  void dispose() { _t?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    // Real ride passed from home polling; fall back to mock load if none provided
    final realRide = ModalRoute.of(context)?.settings.arguments as RideRequestModel?;
    return BlocProvider(
      create: (_) => realRide != null
          ? (RideBloc()..add(SetRideRequestEvent(realRide)))
          : (RideBloc()..add(LoadRideRequestEvent())),
      child: BlocListener<RideBloc, RideState>(
        listener: (context, state) {
          if (state is RideAcceptedState) {
            _t?.cancel();
            Navigator.pushReplacementNamed(context, OnRidePage.route, arguments: state.ride);
          }
          if (state is RideRejectedState) Navigator.pop(context);
          if (state is RideTakenState) {
            _t?.cancel();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Ride already taken')),
            );
            Navigator.pop(context);
          }
        },
        child: BlocBuilder<RideBloc, RideState>(
          builder: (context, state) {
            return Scaffold(
              backgroundColor: AppColors.background,
              body: SafeArea(
                child: state is RideLoading
                    ? const AppLoader()
                    : state is IncomingRideState
                        ? _buildRequest(context, state, context.read<RideBloc>())
                        : const SizedBox(),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildRequest(BuildContext ctx, IncomingRideState state, RideBloc bloc) {
    final r = state.ride;
    final progress = _timer / 20;
    return Column(children: [
      // Timer header
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [AppColors.primaryDark, AppColors.primary]),
        ),
        child: Column(children: [
          Stack(alignment: Alignment.center, children: [
            SizedBox(width: 72, height: 72,
              child: CircularProgressIndicator(value: progress, strokeWidth: 5, color: Colors.white, backgroundColor: Colors.white24),
            ),
            Text('$_timer', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white)),
          ]),
          const SizedBox(height: 8),
          const Text('New Ride Request!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
        ]),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            // User card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.primary,
                  backgroundImage: r.userProfilePicUrl.isNotEmpty ? NetworkImage(r.userProfilePicUrl) : null,
                  child: r.userProfilePicUrl.isEmpty
                    ? Text(r.userName.isNotEmpty ? r.userName[0].toUpperCase() : 'R',
                        style: const TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.w800))
                    : null,
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.userName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textDark)),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.star, color: AppColors.orange, size: 16),
                    Text(' ${r.userRating}', style: const TextStyle(fontSize: 13, color: AppColors.textGrey)),
                  ]),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(r.rideType.toUpperCase(), style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ]),
            ),
            // Outstation badge (only for intercity rides) — driver needs to know departure time + pax
            if (r.service == 'outstation') ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [AppColors.orange.withOpacity(0.15), AppColors.orange.withOpacity(0.05)]),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.orange.withOpacity(0.4)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.map_outlined, color: AppColors.orange, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      r.tripType == 'round_trip' ? 'OUTSTATION • Round Trip' : 'OUTSTATION • One Way',
                      style: const TextStyle(color: AppColors.orange, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.5),
                    ),
                  ]),
                  if (r.cityFrom.isNotEmpty || r.cityTo.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('${r.cityFrom.isNotEmpty ? r.cityFrom : "Pickup"} → ${r.cityTo.isNotEmpty ? r.cityTo : "Destination"}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textDark, fontWeight: FontWeight.w700),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 8),
                  Row(children: [
                    // Departure time chip
                    if (r.departureAt.isNotEmpty) _miniChip(Icons.access_time, _formatIso(r.departureAt)),
                    if (r.departureAt.isNotEmpty) const SizedBox(width: 6),
                    // Return time chip (round trip only)
                    if (r.tripType == 'round_trip' && r.returnAt.isNotEmpty) _miniChip(Icons.replay, _formatIso(r.returnAt)),
                    if (r.tripType == 'round_trip' && r.returnAt.isNotEmpty) const SizedBox(width: 6),
                    // Passengers chip
                    if (r.numPassengers > 0) _miniChip(Icons.group, '${r.numPassengers} pax'),
                  ]),
                ]),
              ),
            ],
            // Rental badge — hourly package hire
            if (r.service == 'rental') ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [AppColors.primary.withOpacity(0.12), AppColors.primary.withOpacity(0.04)]),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withOpacity(0.4)),
                ),
                child: Row(children: [
                  const Icon(Icons.access_time_filled, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Text('RENTAL · ${r.packageHours}hr / ${r.packageKm}km',
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.5)),
                  const Spacer(),
                  if (r.departureAt.isNotEmpty) _miniChip(Icons.event, _formatIso(r.departureAt)),
                ]),
              ),
            ],
            // Hire-a-driver badge — customer's own car
            if (r.service == 'hire_driver') ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity, padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Colors.indigo.withOpacity(0.12), Colors.indigo.withOpacity(0.04)]),
                  borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.indigo.withOpacity(0.4)),
                ),
                child: Row(children: [
                  const Icon(Icons.person_pin_circle, color: Colors.indigo, size: 20),
                  const SizedBox(width: 8),
                  Text('HIRE DRIVER · ${r.hireTotalHours}hr', style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.5)),
                  const Spacer(),
                  if (r.transmission.isNotEmpty) _miniChip(Icons.settings, r.transmission == 'automatic' ? 'Auto' : 'Manual'),
                ]),
              ),
            ],
            // Delivery badge — sender → receiver + item
            if (r.service == 'delivery') ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity, padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Colors.teal.withOpacity(0.12), Colors.teal.withOpacity(0.04)]),
                  borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.teal.withOpacity(0.4)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.local_shipping, color: Colors.teal, size: 20), const SizedBox(width: 8),
                    Text('PARCEL · ${r.itemType.isNotEmpty ? r.itemType : "Delivery"}', style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.5)),
                    const Spacer(),
                    if (r.weightKg > 0) _miniChip(Icons.fitness_center, '${r.weightKg.toStringAsFixed(0)}kg'),
                    if (r.isFragile) ...[const SizedBox(width: 6), _miniChip(Icons.warning_amber, 'Fragile')],
                    if (r.codAmount > 0) ...[const SizedBox(width: 6), _miniChip(Icons.payments, 'COD ₹${r.codAmount.toStringAsFixed(0)}')],
                  ]),
                  if (r.senderName.isNotEmpty || r.receiverName.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('${r.senderName.isNotEmpty ? r.senderName : "Sender"} → ${r.receiverName.isNotEmpty ? r.receiverName : "Receiver"}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textDark, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ]),
              ),
            ],
            const SizedBox(height: 16),
            // Ride info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.divider)),
              child: Column(children: [
                _locationRow(Icons.radio_button_checked, AppColors.green, 'Pickup', r.pickupAddress),
                Padding(
                  padding: const EdgeInsets.only(left: 11),
                  child: Container(width: 2, height: 24, color: AppColors.divider),
                ),
                _locationRow(Icons.location_on, AppColors.red, 'Drop', r.dropAddress),
              ]),
            ),
            const SizedBox(height: 16),
            // Stats row
            Row(children: [
              Expanded(child: _rideStatCard(Icons.route, r.distance, 'Distance')),
              const SizedBox(width: 12),
              Expanded(child: _rideStatCard(Icons.currency_rupee, r.fare.replaceAll('₹ ', ''), 'Fare')),
              const SizedBox(width: 12),
              Expanded(child: _rideStatCard(Icons.timer, r.eta, 'ETA')),
            ]),
            const SizedBox(height: 24),
            // Buttons
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.close, color: AppColors.red),
                  label: const Text('Reject', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.red), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: () => bloc.add(RejectRideEvent(r.id)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text('Accept', style: TextStyle(fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: () => bloc.add(AcceptRideEvent(r.id)),
                ),
              ),
            ]),
          ]),
        ),
      ),
    ]);
  }

  static Widget _miniChip(IconData icon, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.orange.withOpacity(0.4))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: AppColors.orange),
      const SizedBox(width: 4),
      Text(text, style: const TextStyle(fontSize: 10, color: AppColors.textDark, fontWeight: FontWeight.w700)),
    ]),
  );

  static String _formatIso(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      final h = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
      final ampm = d.hour >= 12 ? 'PM' : 'AM';
      return '${d.day}/${d.month} ${h}:${d.minute.toString().padLeft(2, "0")} $ampm';
    } catch (_) { return iso; }
  }

  Widget _locationRow(IconData icon, Color color, String label, String address) {
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textGrey, fontWeight: FontWeight.w600)),
        Text(address, style: const TextStyle(fontSize: 13, color: AppColors.textDark, fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
      ])),
    ]);
  }

  Widget _rideStatCard(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Icon(icon, color: AppColors.primary, size: 20),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textDark, fontSize: 14)),
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textGrey)),
      ]),
    );
  }
}
