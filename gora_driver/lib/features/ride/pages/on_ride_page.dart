import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../models/models.dart';
import '../../../mock/mock_data.dart';
import '../bloc/ride_bloc.dart';
import '../../home/pages/map_placeholder.dart' show RideMap;
import 'invoice_page.dart';

class OnRidePage extends StatelessWidget {
  static const route = '/on-ride';
  const OnRidePage({super.key});

  @override
  Widget build(BuildContext context) {
    final ride = (ModalRoute.of(context)?.settings.arguments as RideRequestModel?) ?? mockRideRequests[0];
    return BlocProvider(
      create: (_) => RideBloc()..currentRide = ride,
      child: BlocListener<RideBloc, RideState>(
        listener: (context, state) {
          if (state is RideEndedState) {
            Navigator.pushReplacementNamed(context, InvoicePage.route, arguments: state.ride);
          }
        },
        child: BlocBuilder<RideBloc, RideState>(
          builder: (context, state) {
            final bloc = context.read<RideBloc>();
            final r = ride;
            // Determine current stage
            bool arrived = state is ArrivedAtPickupState || state is RideStartedState || state is RideEndedState;
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
                    decoration: const BoxDecoration(
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
                        CircleAvatar(radius: 22, backgroundColor: AppColors.primary,
                          child: Text(r.userName[0], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r.userName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textDark)),
                          Text(r.userPhone, style: const TextStyle(color: AppColors.textGrey, fontSize: 13)),
                        ])),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(8)),
                          child: Text(r.fare, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary, fontSize: 16)),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      const Divider(color: AppColors.divider),
                      const SizedBox(height: 12),
                      // Location
                      _locationRow(Icons.radio_button_checked, AppColors.green, started ? 'From' : 'Pickup', r.pickupAddress),
                      const SizedBox(height: 8),
                      _locationRow(Icons.location_on, AppColors.red, 'Drop', r.dropAddress),
                      const SizedBox(height: 20),
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
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                            onPressed: () => _confirmEndRide(context, bloc),
                            child: const Text('🏁 End Ride', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textGrey)),
        Text(addr, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textDark), maxLines: 2),
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
            onPressed: () { Navigator.pop(_); bloc.add(StartRideEvent()); },
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
