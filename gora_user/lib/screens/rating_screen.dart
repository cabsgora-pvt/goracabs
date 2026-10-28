import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/ride_ui/ride_ui.dart';
import 'home_screen.dart';

class RatingScreen extends StatefulWidget {
  final String driverName;
  final String vehicleName;
  final int? selectedTip;
  final String? rideId;
  /// Driver's photo for the header avatar; the initial is shown without one.
  final String driverPhotoUrl;

  const RatingScreen({
    super.key,
    required this.driverName,
    required this.vehicleName,
    this.selectedTip,
    this.rideId,
    this.driverPhotoUrl = '',
  });

  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> {
  int selectedRating = 0;
  final _feedbackController = TextEditingController();

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  static const _labels = ['', 'Terrible', 'Bad', 'Okay', 'Good', 'Excellent'];

  Future<void> _submit() async {
    if (widget.rideId != null) {
      try {
        await ApiService.rateRide(
          widget.rideId!,
          selectedRating,
          _feedbackController.text,
        );
      } catch (_) {}
    }
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const HomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RideUi.surface(context),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.check_circle_rounded, color: Colors.green, size: 16),
                        SizedBox(width: 6),
                        Text('Trip completed', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w800, fontSize: 12.5)),
                      ]),
                    ),
                    const SizedBox(height: 24),
                    DriverAvatar(name: widget.driverName, photoUrl: widget.driverPhotoUrl, radius: 46),
                    const SizedBox(height: 18),
                    Text(
                      'How was your ride with ${widget.driverName}?',
                      textAlign: TextAlign.center,
                      style: RideUi.title(context, size: 22),
                    ),
                    if (widget.vehicleName.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(widget.vehicleName, style: RideUi.caption(context, size: 13.5)),
                    ],
                    const SizedBox(height: 26),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(5, (index) {
                          return IconButton(
                            onPressed: () {
                              setState(() {
                                selectedRating = index + 1;
                              });
                            },
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            constraints: const BoxConstraints(),
                            icon: Icon(
                              index < selectedRating ? Icons.star_rounded : Icons.star_outline_rounded,
                              color: index < selectedRating ? const Color(0xFFFFB300) : RideUi.muted(context),
                              size: 50,
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 20,
                      child: Text(_labels[selectedRating], style: RideUi.body(context, size: 14, weight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 22),
                    TextField(
                      controller: _feedbackController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Write your feedback about the driver and ride...',
                        hintStyle: RideUi.caption(context, size: 14),
                        filled: true,
                        fillColor: RideUi.tile(context),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFF1C2656), width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: PrimaryRideButton(
                label: 'Submit Rating',
                onPressed: selectedRating == 0 ? null : _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
