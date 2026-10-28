import 'package:flutter/material.dart';
import 'home_screen.dart';
import '../widgets/ride_ui/ride_ui.dart';

class HireDriverBookingDetailsScreen extends StatelessWidget {
  final String inquiryId;
  final String pickupLocation;
  final String dropLocation;
  final String carType;
  final String hireDuration;
  final String package;
  final String price;
  final String tripStartDate;
  final String tripTime;
  final String? driverName;
  final String? driverRating;
  final String? driverPhone;
  final String? driverExperience;
  final String? vehicleNumber;
  final String? vehicleModel;
  final String? vehicleColor;
  // Extra summary fields (screenshot layout). All optional — sensible defaults
  // are derived from the existing fields when not supplied.
  final String? bookingDate;
  final String? bookingTime;
  final String? tripEndDate;
  final String? noOfDays;
  final String tripType; // 'one_way' | 'round_trip'
  final String? gearType;
  final String? visitingLocation;

  const HireDriverBookingDetailsScreen({
    Key? key,
    required this.inquiryId,
    required this.pickupLocation,
    required this.dropLocation,
    required this.carType,
    required this.hireDuration,
    required this.package,
    required this.price,
    required this.tripStartDate,
    required this.tripTime,
    this.driverName,
    this.driverRating,
    this.driverPhone,
    this.driverExperience,
    this.vehicleNumber,
    this.vehicleModel,
    this.vehicleColor,
    this.bookingDate,
    this.bookingTime,
    this.tripEndDate,
    this.noOfDays,
    this.tripType = 'one_way',
    this.gearType,
    this.visitingLocation,
  }) : super(key: key);

  // ── Derived summary values (used by the screenshot-style rows) ──
  int _dayCount() {
    final m = RegExp(r'\d+').firstMatch(noOfDays ?? package);
    return m != null ? int.parse(m.group(0)!) : 1;
  }

  String _endDate() {
    if (tripEndDate != null && tripEndDate!.isNotEmpty) return tripEndDate!;
    try {
      final p = tripStartDate.split('/');
      if (p.length != 3) return '';
      final d = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0])).add(Duration(days: _dayCount()));
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) {
      return '';
    }
  }

  String get _tripLabel => tripType == 'round_trip' ? 'Round Trip' : tripType == 'one_way' ? 'One Way' : tripType;

  @override
  Widget build(BuildContext context) {
    void home() => Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
          (route) => false,
        );
    return ServiceSummaryPage(
      title: 'Hire Driver Details',
      subtitle: 'Inquiry ID: $inquiryId',
      onHome: home,
      children: [
        SummaryVehicleTile(
          leading: const VehicleThumb(fallbackIcon: Icons.person_pin_outlined, size: 48),
          name: carType,
          caption: '$hireDuration · $_tripLabel',
          price: price,
          priceCaption: 'Approximate Price',
        ),
        const SizedBox(height: 12),
        SummaryRouteTile(pickup: pickupLocation, drop: dropLocation),

        // Driver (once assigned)
        if (driverName != null) ...[
          const ServiceSection('Driver Details', top: 20),
          AssignedDriverCard(
            name: driverName!,
            rating: driverRating,
            experience: driverExperience,
            phone: driverPhone,
          ),
        ],
        // The rider's own car
        if (vehicleNumber != null) ...[
          const ServiceSection('Your Vehicle Details', top: 20),
          SummaryVehicleTile(
            leading: const VehicleThumb(fallbackIcon: Icons.directions_car, size: 40),
            name: (vehicleModel == null || vehicleModel!.isEmpty) ? carType : vehicleModel!,
            caption: [vehicleNumber, vehicleColor].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
          ),
        ],

        const ServiceSection('Booking Summary', top: 20),
        SummaryRow('Booking Date', _orDash(bookingDate ?? tripStartDate)),
        SummaryRow('Booking Time', _orDash(bookingTime ?? tripTime)),
        SummaryRow('Trip start date', _orDash(tripStartDate)),
        SummaryRow('Trip end date', _orDash(_endDate())),
        SummaryRow('No. of days', '${_dayCount()}'),
        SummaryRow('Trip', _orDash(_tripLabel)),
        SummaryRow('Car Type', _orDash(carType)),
        SummaryRow('Gear Type', (gearType == null || gearType!.isEmpty) ? 'Manual' : gearType!),
        SummaryRow('Visiting Location',
            _orDash((visitingLocation == null || visitingLocation!.isEmpty) ? dropLocation : visitingLocation!)),
        const RideDivider(vertical: 8),
        SummaryRow('No of Days', package),
        SummaryRow('Approximate Price', price, bold: true),

        const SizedBox(height: 16),
        const CollapsibleInfo(
          title: 'Service Conditions',
          icon: Icons.info_outline,
          children: [
            InfoLine(Icons.person_outline, 'Professional verified driver will be assigned'),
            InfoLine(Icons.directions_car_outlined, 'Driver will drive your personal vehicle'),
            InfoLine(Icons.toll, 'Tolls and parking extra (pay directly)'),
            InfoLine(Icons.schedule, 'Overtime charges apply beyond package duration'),
            SizedBox(height: 6),
            NoticeRow('Please ensure car documents and fuel are ready', tone: NoticeTone.warning),
          ],
        ),
        const SizedBox(height: 10),
        const CollapsibleInfo(
          title: 'Extra charges',
          icon: Icons.receipt_long_outlined,
          children: [
            InfoLine(Icons.nightlight_outlined, 'At 11pm ₹200 for night allowance'),
            InfoLine(Icons.wb_twilight, 'Till 6am ₹200 for early morning charge'),
            InfoLine(Icons.more_time, 'Per hour overtime ₹100'),
            InfoLine(Icons.event_busy_outlined, 'If you release the driver at 4 am then next day charges ₹1500 is applicable'),
            InfoLine(Icons.restaurant_outlined, 'Food charges ₹200 per day'),
          ],
        ),
      ],
    );
  }

  static String _orDash(String v) => v.isEmpty ? '—' : v;
}
