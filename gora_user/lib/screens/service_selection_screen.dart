import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'taxi_booking_screen.dart';
import 'outstation_screen.dart';
import 'rental_screen.dart';
import 'hire_driver_screen.dart';
import 'parcel_booking_screen.dart';
import 'mini_ride_screen.dart';
import 'prime_ride_screen.dart';
import 'inquiry_screen.dart';
import 'support_screen.dart';

class ServiceSelectionScreen extends StatelessWidget {
  const ServiceSelectionScreen({super.key});

  final List<Map<String, dynamic>> _services = const [
    {'icon': 'assets/images/bike.png', 'label': 'Bike ride', 'color': Color(0xFF2196F3), 'bgColor': Color(0xFFE3F2FD)},
    {'icon': 'assets/images/auto.jpg', 'label': 'Auto ride', 'color': Color(0xFF4CAF50), 'bgColor': Color(0xFFE8F5E9)},
    {'icon': 'assets/images/texi.png', 'label': 'Cab ride', 'color': Color(0xFF2196F3), 'bgColor': Color(0xFFE3F2FD)},
    {'icon': 'assets/images/rental.png', 'label': 'Rentals', 'color': Color(0xFFFF9800), 'bgColor': Color(0xFFFFF3E0)},
    {'icon': 'assets/images/out-station.png', 'label': 'Outstation', 'color': Color(0xFF4CAF50), 'bgColor': Color(0xFFE8F5E9)},
    {'icon': 'assets/images/parcel.jpg', 'label': 'Parcel', 'color': Color(0xFF2196F3), 'bgColor': Color(0xFFE3F2FD)},
    {'icon': 'assets/images/hiredriver.png', 'label': 'Hire driver', 'color': Color(0xFF9C27B0), 'bgColor': Color(0xFFF3E5F5)},
    {'icon': 'assets/images/texi2.png', 'label': 'Mini Ride', 'color': Color(0xFFFF9800), 'bgColor': Color(0xFFFFF3E0)},
    {'icon': 'assets/images/texi3.png', 'label': 'Prime Ride', 'color': Color(0xFF9C27B0), 'bgColor': Color(0xFFF3E5F5)},
    {'icon': 'assets/images/query.jpg', 'label': 'Any inquiry', 'color': Color(0xFF4CAF50), 'bgColor': Color(0xFFE8F5E9)},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Align(
          alignment: Alignment.centerLeft,
          child: Text('All Services'),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: _services.length,
        itemBuilder: (context, index) {
          final service = _services[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            child: _buildServiceItem(context, service),
          );
        },
      ),
    );
  }

  Widget _buildServiceItem(BuildContext context, Map<String, dynamic> service) {
    return GestureDetector(
      onTap: () {
        if (service['label'] == 'Bike ride') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TaxiBookingScreen(
                fromLocation: 'Current Location',
                hideLocationInputs: false,
                preselectedVehicle: 'Bike',
              ),
            ),
          );
        } else if (service['label'] == 'Auto ride') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TaxiBookingScreen(
                fromLocation: 'Current Location',
                hideLocationInputs: false,
                preselectedVehicle: 'Auto',
              ),
            ),
          );
        } else if (service['label'] == 'Cab ride') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TaxiBookingScreen(
                fromLocation: 'Current Location',
                hideLocationInputs: false,
                preselectedVehicle: 'Cab Economy',
              ),
            ),
          );
        } else if (service['label'] == 'Outstation') {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const OutstationScreen()));
        } else if (service['label'] == 'Rentals') {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const RentalScreen()));
        } else if (service['label'] == 'Hire driver') {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const HireDriverScreen()));
        } else if (service['label'] == 'Parcel') {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const ParcelBookingScreen()));
        } else if (service['label'] == 'Mini Ride') {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const MiniRideScreen()));
        } else if (service['label'] == 'Prime Ride') {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const PrimeRideScreen()));
        } else if (service['label'] == 'Any inquiry') {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const InquiryScreen()));
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: service['bgColor'] as Color,
                borderRadius: BorderRadius.circular(16),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  service['icon'] as String,
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(
                      Icons.directions_car,
                      color: service['color'] as Color,
                      size: 24,
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                service['label'] as String,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }
}

