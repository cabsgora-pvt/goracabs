import 'package:flutter/material.dart';
import '../screens/emergency_actions_screen.dart';

// Full-width red "SOS / Emergency" button used on every ongoing-ride view.
Widget sosButton(BuildContext context, String? rideId) => GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EmergencyActionsScreen(rideId: rideId))),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red),
        ),
        child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.sos, color: Colors.red),
          SizedBox(width: 8),
          Text('SOS / Emergency', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
