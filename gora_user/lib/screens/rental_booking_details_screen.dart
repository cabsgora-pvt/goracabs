import 'package:flutter/material.dart';
import 'home_screen.dart';
import '../widgets/ride_ui/ride_ui.dart';

class RentalBookingDetailsScreen extends StatelessWidget {
  final String inquiryId;
  final String pickupLocation;
  final String dropLocation;
  final String duration;
  final String vehicle;
  final String price;
  final String date;
  final String time;
  final String? driverName;
  final String? driverRating;
  final String? driverPhone;
  final String? driverExperience;
  final String? vehicleNumber;
  final String? vehicleModel;
  final String? vehicleColor;

  const RentalBookingDetailsScreen({
    Key? key,
    required this.inquiryId,
    required this.pickupLocation,
    required this.dropLocation,
    required this.duration,
    required this.vehicle,
    required this.price,
    required this.date,
    required this.time,
    this.driverName,
    this.driverRating,
    this.driverPhone,
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
      title: 'Rental Booking Details',
      subtitle: 'Inquiry ID: $inquiryId',
      onHome: home,
      children: [
        SummaryVehicleTile(
          leading: const VehicleThumb(fallbackIcon: Icons.directions_car, size: 48),
          name: vehicle,
          caption: duration,
          price: price,
          priceCaption: 'Total Price',
        ),
        const SizedBox(height: 12),
        SummaryRouteTile(pickup: pickupLocation, drop: dropLocation),

        // Driver and vehicle (once assigned)
        if (driverName != null) ...[
          const ServiceSection('Driver Details', top: 20),
          AssignedDriverCard(
            name: driverName!,
            rating: driverRating,
            experience: driverExperience,
            phone: driverPhone,
            vehicleModel: vehicleModel,
            vehicleColor: vehicleColor,
            vehicleNumber: vehicleNumber,
          ),
        ] else if (vehicleNumber != null) ...[
          const ServiceSection('Vehicle Details', top: 20),
          SummaryVehicleTile(
            leading: const VehicleThumb(fallbackIcon: Icons.directions_car, size: 40),
            name: vehicleModel ?? vehicle,
            caption: [vehicleNumber, vehicleColor].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
          ),
        ],

        const ServiceSection('Booking Summary', top: 20),
        SummaryRow('Duration', duration, icon: Icons.schedule),
        SummaryRow('Vehicle', vehicle, icon: Icons.directions_car_outlined),
        SummaryRow('Date', date, icon: Icons.calendar_today_outlined),
        SummaryRow('Time', time, icon: Icons.access_time),
        const RideDivider(vertical: 8),
        SummaryRow('Total Price', price, bold: true),

        const SizedBox(height: 16),
        const CollapsibleInfo(
          title: 'Rental Benefits',
          icon: Icons.verified_outlined,
          children: [
            InfoLine(Icons.alt_route, 'Unlimited stops within package duration'),
            InfoLine(Icons.verified_user_outlined, 'Professional and verified pilot'),
            InfoLine(Icons.cleaning_services_outlined, 'Clean and well-maintained vehicle'),
            InfoLine(Icons.lock_clock_outlined, 'Fixed price with no surge charges'),
          ],
        ),
        const SizedBox(height: 10),
        const CollapsibleInfo(
          title: 'Rental Conditions',
          icon: Icons.info_outline,
          children: [
            InfoLine(Icons.toll, 'Tolls and parking charges are extra'),
            InfoLine(Icons.local_gas_station_outlined, 'Fuel included in the package'),
            InfoLine(Icons.more_time, 'Overtime charges ₹150 per hour beyond package duration'),
            InfoLine(Icons.nightlight_outlined, 'Night charges (11 PM - 6 AM) ₹200 extra'),
            InfoLine(Icons.person_outline, 'Driver allowance ₹200 per day for outstation'),
            SizedBox(height: 6),
            NoticeRow('Additional charges to be paid directly to driver', icon: Icons.payments_outlined, tone: NoticeTone.warning),
          ],
        ),
      ],
    );
  }
}
