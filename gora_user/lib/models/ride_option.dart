import 'package:flutter/material.dart';

class RideOption {
  final String name;
  final String description;
  final String price;
  final IconData icon;

  const RideOption({
    required this.name,
    required this.description,
    required this.price,
    required this.icon,
  });
}

const List<RideOption> rideOptions = [
  RideOption(
    name: 'Gora Go',
    description: 'Affordable, everyday rides',
    price: '₹120',
    icon: Icons.directions_car,
  ),
  RideOption(
    name: 'Gora Premier',
    description: 'Top-rated drivers, newer cars',
    price: '₹180',
    icon: Icons.star,
  ),
  RideOption(
    name: 'Gora XL',
    description: 'Comfortable SUVs for groups',
    price: '₹250',
    icon: Icons.airport_shuttle,
  ),
];
