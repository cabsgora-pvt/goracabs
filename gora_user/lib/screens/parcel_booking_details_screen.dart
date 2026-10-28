import 'dart:io';
import 'package:flutter/material.dart';
import '../widgets/ride_ui/ride_ui.dart';
import 'home_screen.dart';

class ParcelBookingDetailsScreen extends StatelessWidget {
  final String inquiryId;
  final String pickupLocation;
  final String dropLocation;
  final String itemType;
  final String weight;
  final String vehicle;
  final String receiverName;
  final String receiverPhone;
  final List<String> imagePaths;
  final String? driverName;
  final String? driverRating;
  final String? driverExperience;
  final String? vehicleNumber;
  final String? vehicleModel;
  final String? vehicleColor;

  const ParcelBookingDetailsScreen({
    Key? key,
    required this.inquiryId,
    required this.pickupLocation,
    required this.dropLocation,
    required this.itemType,
    required this.weight,
    required this.vehicle,
    required this.receiverName,
    required this.receiverPhone,
    required this.imagePaths,
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
      title: 'Booking Confirmed',
      subtitle: 'Inquiry ID: $inquiryId',
      status: 'Your parcel is ready for pickup!',
      homeLabel: 'Done',
      onHome: home,
      children: [
        SummaryVehicleTile(
          leading: const VehicleThumb(fallbackIcon: Icons.local_shipping_outlined, size: 48),
          name: vehicle,
          caption: '$itemType · $weight kg',
        ),

        // Delivery Route
        const ServiceSection('Delivery Route', top: 20),
        SummaryRouteTile(pickup: pickupLocation, drop: dropLocation),

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

        // Parcel Details
        const ServiceSection('Parcel Details', top: 20),
        SummaryRow('Type', itemType, icon: Icons.inventory_2_outlined),
        SummaryRow('Weight', '$weight kg', icon: Icons.fitness_center_outlined),
        SummaryRow('Vehicle', vehicle, icon: Icons.local_shipping_outlined),
        SummaryRow('Receiver', receiverName, icon: Icons.person_outline),
        if (receiverPhone.isNotEmpty) SummaryRow('Receiver phone', receiverPhone, icon: Icons.phone_outlined),

        // Parcel Images
        if (imagePaths.isNotEmpty) ...[
          const ServiceSection('Parcel Images', top: 20),
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: imagePaths.length,
              itemBuilder: (context, index) {
                return Container(
                  width: 100,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    image: DecorationImage(
                      image: FileImage(File(imagePaths[index])),
                      fit: BoxFit.cover,
                    ),
                  ),
                );
              },
            ),
          ),
        ],

        // Conditions
        const SizedBox(height: 16),
        const CollapsibleInfo(
          title: 'Delivery conditions',
          icon: Icons.info_outline,
          initiallyExpanded: true,
          children: [
            InfoLine(Icons.security_outlined, 'Parcel contents must be legal and safe'),
            InfoLine(Icons.timer_outlined, 'Standard delivery time: 1-2 hours'),
            InfoLine(Icons.payment_outlined, 'Tolls/Parking extra (if applicable)'),
          ],
        ),
      ],
    );
  }
}
