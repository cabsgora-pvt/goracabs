import 'package:flutter/material.dart';
import 'home_screen.dart';
import '../widgets/ride_ui/ride_ui.dart';

class OutstationRideDetailsScreen extends StatelessWidget {
  final String inquiryId;
  final String fromLocation;
  final String toLocation;
  final String vehicleName;
  final String vehicleType;
  final String capacity;
  final String tripType;
  final String departureDate;
  final String departureTime;
  final String? returnDate;
  final String? returnTime;
  final String price;
  final String estimatedDistance;
  final String estimatedDuration;
  final String? driverName;
  final String? driverRating;
  final String? driverExperience;
  final String? vehicleNumber;
  final String? vehicleModel;
  final String? vehicleColor;

  const OutstationRideDetailsScreen({
    Key? key,
    required this.inquiryId,
    required this.fromLocation,
    required this.toLocation,
    required this.vehicleName,
    required this.vehicleType,
    required this.capacity,
    required this.tripType,
    required this.departureDate,
    required this.departureTime,
    this.returnDate,
    this.returnTime,
    required this.price,
    required this.estimatedDistance,
    required this.estimatedDuration,
    this.driverName,
    this.driverRating,
    this.driverExperience,
    this.vehicleNumber,
    this.vehicleModel,
    this.vehicleColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    void home() => Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
          (route) => false,
        );
    return ServiceSummaryPage(
      title: 'Outstation Trip Details',
      subtitle: 'Inquiry ID: $inquiryId',
      status: 'Trip Confirmed!',
      onHome: home,
      children: [
        SummaryVehicleTile(
          leading: const VehicleThumb(fallbackIcon: Icons.directions_car, size: 48),
          name: vehicleName,
          caption: '$vehicleType • $capacity seats',
          price: price,
          priceCaption: 'Total Fare',
        ),
        const SizedBox(height: 12),
        SummaryRouteTile(
          pickup: fromLocation,
          drop: toLocation,
          footer: Row(children: [
            Icon(Icons.route, size: 16, color: RideUi.ink(context)),
            const SizedBox(width: 6),
            Expanded(
              child: Text('$estimatedDistance · $estimatedDuration · $tripType',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: RideUi.body(context, size: 13, weight: FontWeight.w700)),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        PickerPill(icon: Icons.event_outlined, label: 'Departure', value: '$departureDate • $departureTime'),
        if (tripType == 'Round Trip' && returnDate != null) ...[
          const SizedBox(height: 8),
          PickerPill(icon: Icons.event_repeat, label: 'Return', value: '$returnDate • ${returnTime ?? 'TBD'}'),
        ],

        // Driver and vehicle (once assigned)
        if (driverName != null) ...[
          const ServiceSection('Driver Details', top: 20),
          AssignedDriverCard(
            name: driverName!,
            rating: driverRating,
            experience: driverExperience,
            vehicleModel: vehicleModel,
            vehicleColor: vehicleColor,
            vehicleNumber: vehicleNumber,
          ),
        ],

        const ServiceSection('Trip Summary', top: 20),
        SummaryRow('Trip Type', tripType),
        SummaryRow('Estimated Distance', estimatedDistance),
        SummaryRow('Estimated Duration', estimatedDuration),
        const RideDivider(vertical: 8),
        SummaryRow('Total Fare', price, bold: true),

        const SizedBox(height: 16),
        const CollapsibleInfo(
          title: "What's Included",
          icon: Icons.check_circle_outline,
          children: [
            InfoLine(Icons.verified_user_outlined, 'Professional verified driver'),
            InfoLine(Icons.local_gas_station_outlined, 'Fuel included in base fare'),
            InfoLine(Icons.ac_unit, 'AC vehicle with comfortable seats'),
            InfoLine(Icons.gps_fixed, 'Live GPS tracking'),
          ],
        ),
        const SizedBox(height: 10),
        CollapsibleInfo(
          title: 'Additional Charges',
          icon: Icons.receipt_long_outlined,
          children: [
            const InfoLine(Icons.toll, 'Tolls and state taxi extra pay'),
            const InfoLine(Icons.local_parking, 'Parking charges extra'),
            if (tripType != 'One Way') ...const [
              InfoLine(Icons.route, 'Minimum per day 250km running'),
              InfoLine(Icons.person_outline, 'Driver allowance per 24 hours - ₹250'),
              InfoLine(Icons.nightlight_outlined, 'Night drive allowance - ₹250/night'),
            ],
            const SizedBox(height: 6),
            const NoticeRow('Customer - pay the driver directly', icon: Icons.payments_outlined, tone: NoticeTone.warning),
          ],
        ),
      ],
    );
  }
}
