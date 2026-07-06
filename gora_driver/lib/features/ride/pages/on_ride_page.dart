import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/models.dart';
import '../../../mock/mock_data.dart';
import '../../../services/driver_api_service.dart';
import '../bloc/ride_bloc.dart';
import '../../home/pages/map_placeholder.dart' show RideMap;
import 'invoice_page.dart';
import 'rental_progress_page.dart';
import 'hire_progress_page.dart';
import 'delivery_progress_page.dart';

class OnRidePage extends StatelessWidget {
  static const route = '/on-ride';
  const OnRidePage({super.key});

  // Tracks outstation phase locally (UI-only — backend update via DriverApiService.updatePhase)
  static final ValueNotifier<String> _outstationPhase = ValueNotifier<String>('enroute');
  static final ValueNotifier<bool> _nightHaltConfirmed = ValueNotifier<bool>(false);
  // Multi-stop progress: current stop index + waiting flag
  static final ValueNotifier<int> _stopIndex = ValueNotifier<int>(0);
  static final ValueNotifier<bool> _waitingAtStop = ValueNotifier<bool>(false);

  @override
  Widget build(BuildContext context) {
    final ride = (ModalRoute.of(context)?.settings.arguments as RideRequestModel?) ?? mockRideRequests[0];
    return BlocProvider(
      create: (_) => RideBloc()..currentRide = ride,
      child: BlocListener<RideBloc, RideState>(
        listener: (context, state) {
          // Rental: once OTP-started, go to the live rental-progress screen instead of plain end
          if (state is RideStartedState && ride.service == 'rental') {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => RentalProgressPage(ride: ride)));
            return;
          }
          // Hire: once OTP-started, go to the live hire-progress screen
          if (state is RideStartedState && ride.service == 'hire_driver') {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HireProgressPage(ride: ride)));
            return;
          }
          // Delivery: once collected via pickup OTP, go to the delivery flow (collect → drop OTP)
          if (state is RideStartedState && ride.service == 'delivery') {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => DeliveryProgressPage(ride: ride)));
            return;
          }
          if (state is RideEndedState) {
            Navigator.pushReplacementNamed(
              context, InvoicePage.route,
              arguments: RideCompletionArgs(
                state.ride,
                driverEarning: state.driverEarning,
                adminProfit: state.adminProfit,
              ),
            );
          }
          if (state is OtpErrorState) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Invalid OTP')),
            );
          }
        },
        child: BlocBuilder<RideBloc, RideState>(
          builder: (context, state) {
            final bloc = context.read<RideBloc>();
            final r = ride;
            // Determine current stage
            bool arrived = state is ArrivedAtPickupState || state is RideStartedState || state is RideEndedState || state is OtpErrorState;
            bool started = state is RideStartedState;

            return Scaffold(
              body: Stack(children: [
                RideMap(
                  pickupLat: r.pickupLat,
                  pickupLng: r.pickupLng,
                  dropLat: r.dropLat,
                  dropLng: r.dropLng,
                ),
                // Top bar
                Positioned(
                  top: 0, left: 0, right: 0,
                  child: Container(
                    padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 8, left: 16, right: 16, bottom: 12),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: [AppColors.primaryDark, AppColors.primary]),
                    ),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
                        child: Row(children: [
                          Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Text(started ? 'ON TRIP' : arrived ? 'ARRIVED' : 'PICKUP', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                        ]),
                      ),
                      const Spacer(),
                      IconButton(icon: const Icon(Icons.chat_bubble_outline, color: Colors.white), onPressed: () => _showChat(context, r)),
                      IconButton(icon: const Icon(Icons.phone, color: Colors.white), onPressed: () {}),
                    ]),
                  ),
                ),
                // Bottom sheet
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                      boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 16)],
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      // Handle
                      Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2))),
                      const SizedBox(height: 16),
                      // User
                      Row(children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: AppColors.primary,
                          backgroundImage: r.userProfilePicUrl.isNotEmpty ? NetworkImage(r.userProfilePicUrl) : null,
                          child: r.userProfilePicUrl.isEmpty
                            ? Text(r.userName.isNotEmpty ? r.userName[0].toUpperCase() : 'R',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))
                            : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r.userName, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textDark)),
                          Text(r.userPhone, style: TextStyle(color: AppColors.textGrey, fontSize: 13)),
                        ])),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(8)),
                          child: Text(r.fare, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary, fontSize: 16)),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      Divider(color: AppColors.divider),
                      const SizedBox(height: 12),
                      // Location
                      _locationRow(Icons.radio_button_checked, AppColors.green, started ? 'From' : 'Pickup', r.pickupAddress),
                      // Multi-stop list (A → stops → drop)
                      if (r.stops.isNotEmpty) ...r.stops.asMap().entries.map((e) => Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _locationRow(Icons.trip_origin, AppColors.orange, 'Stop ${e.key + 1}', (e.value['address'] ?? '').toString()))),
                      const SizedBox(height: 8),
                      _locationRow(Icons.location_on, AppColors.red, 'Drop', r.dropAddress),
                      const SizedBox(height: 20),
                      // Multi-stop progress controls (only while ride is ongoing)
                      if (started && r.stops.isNotEmpty)
                        ValueListenableBuilder<int>(valueListenable: _stopIndex, builder: (_, idx, __) =>
                          ValueListenableBuilder<bool>(valueListenable: _waitingAtStop, builder: (_, waiting, __) {
                            if (idx >= r.stops.length) return const SizedBox.shrink();
                            final stopName = (r.stops[idx]['address'] ?? 'Stop ${idx + 1}').toString();
                            return Padding(padding: const EdgeInsets.only(bottom: 12), child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: AppColors.orange.withOpacity(0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.orange.withOpacity(0.4))),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('Next: Stop ${idx + 1} of ${r.stops.length}', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.orange, fontSize: 12)),
                                Text(stopName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 10),
                                if (!waiting)
                                  PrimaryButton(label: '📍 Reached Stop ${idx + 1}', onTap: () async {
                                    await DriverApiService.stopAction(r.id, {'action': 'reached', 'index': idx});
                                    _waitingAtStop.value = true;
                                  })
                                else Column(children: [
                                  Text('⏳ Waiting — customer doing their work', style: TextStyle(fontSize: 12, color: AppColors.textGrey)),
                                  const SizedBox(height: 8),
                                  PrimaryButton(label: '▶ Resume / Next', onTap: () async {
                                    await DriverApiService.stopAction(r.id, {'action': 'resume', 'index': idx});
                                    _waitingAtStop.value = false;
                                    _stopIndex.value = idx + 1;
                                  }),
                                ]),
                              ]),
                            ));
                          })),
                      // Action button
                      if (state is RideLoading)
                        const AppLoader()
                      else ...[
                        if (!arrived)
                          PrimaryButton(
                            label: '📍 I have Arrived',
                            onTap: () => bloc.add(ArrivedEvent()),
                          ),
                        if (arrived && !started)
                          PrimaryButton(
                            label: '🚀 Start Ride',
                            onTap: () => _showOtpDialog(context, bloc),
                          ),
                        if (started)
                          // Outstation round-trip needs intermediate "at destination" + optional night halt + "start return"
                          // For one-way / taxi, fall through to the standard End Ride button.
                          ValueListenableBuilder<String>(
                            valueListenable: _outstationPhase,
                            builder: (_, phase, __) {
                              final isOutstation = r.service == 'outstation';
                              final isRound = isOutstation && r.tripType == 'round_trip';

                              if (isRound && phase == 'enroute') {
                                return Column(children: [
                                  PrimaryButton(
                                    label: '📍 Arrived at Destination',
                                    onTap: () async {
                                      await DriverApiService.updatePhase(r.id, {'phase': 'at_destination'});
                                      _outstationPhase.value = 'at_destination';
                                    },
                                  ),
                                ]);
                              }
                              if (isRound && phase == 'at_destination') {
                                return Column(children: [
                                  // Night halt confirm — toggles once
                                  ValueListenableBuilder<bool>(
                                    valueListenable: _nightHaltConfirmed,
                                    builder: (_, confirmed, __) => OutlinedButton.icon(
                                      onPressed: confirmed ? null : () async {
                                        await DriverApiService.updatePhase(r.id, {'confirmNightHalt': true});
                                        _nightHaltConfirmed.value = true;
                                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Night halt confirmed'), backgroundColor: AppColors.green),
                                        );
                                      },
                                      icon: Icon(Icons.bedtime, color: confirmed ? Colors.grey : AppColors.orange),
                                      label: Text(confirmed ? 'Night halt confirmed' : 'Confirm Night Halt (optional)'),
                                      style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48), side: BorderSide(color: confirmed ? Colors.grey : AppColors.orange)),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  PrimaryButton(
                                    label: '↻ Start Return Journey',
                                    onTap: () async {
                                      await DriverApiService.updatePhase(r.id, {'phase': 'returning'});
                                      _outstationPhase.value = 'returning';
                                    },
                                  ),
                                ]);
                              }
                              // Default: standard End Ride (one-way outstation, taxi, or round-trip returning)
                              return ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: AppColors.red, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                onPressed: () {
                                  _outstationPhase.value = 'enroute';  // reset for next ride
                                  _nightHaltConfirmed.value = false;
                                  _stopIndex.value = 0; _waitingAtStop.value = false;
                                  _confirmEndRide(context, bloc);
                                },
                                child: const Text('🏁 End Ride', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                              );
                            },
                          ),
                      ],
                    ]),
                  ),
                ),
              ]),
            );
          },
        ),
      ),
    );
  }

  Widget _locationRow(IconData icon, Color color, String label, String addr) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 10, color: AppColors.textGrey)),
        Text(addr, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textDark), maxLines: 2),
      ])),
    ]);
  }

  void _showOtpDialog(BuildContext context, RideBloc bloc) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Enter Ride OTP', style: TextStyle(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          maxLength: 4,
          decoration: const InputDecoration(labelText: 'OTP from Rider', hintText: 'e.g. 5678'),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 8),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () { final otp = ctrl.text.trim(); Navigator.pop(_); bloc.add(StartRideEvent(otp)); },
            child: const Text('Start'),
          ),
        ],
      ),
    );
  }

  void _confirmEndRide(BuildContext context, RideBloc bloc) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('End Ride?', style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text('Are you sure you want to end this ride?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () { Navigator.pop(_); bloc.add(EndRideEvent()); },
            child: const Text('End Ride', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showChat(BuildContext context, RideRequestModel r) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6, maxChildSize: 0.9, minChildSize: 0.4, expand: false,
        builder: (_, ctrl) => Column(children: [
          Container(margin: const EdgeInsets.only(top: 8), width: 40, height: 4, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2))),
          Padding(padding: const EdgeInsets.all(16), child: Row(children: [
            const Text('Chat with Rider', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ])),
          Expanded(child: ListView(controller: ctrl, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
            _chatBubble("Hi, I'm here!", false),
            _chatBubble("Please reach gate 2", true),
            _chatBubble("Coming in 2 mins", false),
          ])),
          Padding(
            padding: EdgeInsets.only(left: 16, right: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
            child: Row(children: [
              const Expanded(child: TextField(decoration: InputDecoration(hintText: 'Type message...'))),
              const SizedBox(width: 8),
              IconButton(icon: const Icon(Icons.send, color: AppColors.primary), onPressed: () {}),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _chatBubble(String msg, bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? AppColors.primary : AppColors.cardBg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(msg, style: TextStyle(color: isMe ? Colors.white : AppColors.textDark)),
      ),
    );
  }
}
