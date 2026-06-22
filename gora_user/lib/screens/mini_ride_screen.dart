import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme/app_theme.dart';
import 'booking_screen.dart';
import 'home_screen.dart';
import 'rating_screen.dart';

class MiniRideScreen extends StatefulWidget {
  final String? fromLocation;
  final String? toLocation;
  final bool hideLocationInputs;
  
  const MiniRideScreen({
    super.key,
    this.fromLocation,
    this.toLocation,
    this.hideLocationInputs = false,
  });

  @override
  State<MiniRideScreen> createState() => _MiniRideScreenState();
}

class _MiniRideScreenState extends State<MiniRideScreen> {
  String? _selectedVehicle;
  final _pickupController = TextEditingController();
  final _dropController = TextEditingController();
  bool _showLocationInputs = false;
  bool _showPickupConfirmation = false;
  bool _showWaitingPopup = false;
  int? _selectedTip;
  bool _isTaxiComing = false;
  LatLng? _comingTaxiLocation;
  bool _locationConfirmed = false;
  bool _showFullTripMap = false;
  bool _showArrivingButtons = false;
  
  final List<int> _tipAmounts = [10, 20, 50, 100];

  @override
  void initState() {
    super.initState();
    // Set default locations
    _pickupController.text = widget.fromLocation ?? 'Current Location';
    _dropController.text = widget.toLocation ?? 'Select Destination';
    
    // If locations are already provided, consider it confirmed
    if (widget.fromLocation != null && widget.toLocation != null) {
      _locationConfirmed = true;
    }
  }

  // Economy car locations (4 cars)
  final List<LatLng> _economyLocations = [
    LatLng(28.6140, 77.2095),
    LatLng(28.6158, 77.2088),
    LatLng(28.6122, 77.2102),
    LatLng(28.6162, 77.2078),
  ];

  // SUV locations (2 cars)
  final List<LatLng> _suvLocations = [
    LatLng(28.6148, 77.2092),
    LatLng(28.6152, 77.2098),
  ];

  // Premium car locations (1 car)
  final List<LatLng> _premiumLocations = [
    LatLng(28.6145, 77.2090),
  ];

  final List<Map<String, dynamic>> _vehicles = [
    {'name': 'Cab Economy', 'type': 'Comfortable', 'price': '₹144', 'eta': '4 min', 'capacity': '4', 'icon': Icons.directions_car, 'color': Color(0xFF1C2656), 'image': 'assets/images/economy.png'},
    {'name': 'SUV', 'type': 'Spacious', 'price': '₹250', 'eta': '5 min', 'capacity': '6', 'icon': Icons.airport_shuttle, 'color': Color(0xFF1C2656), 'image': 'assets/images/texi.png'},
    {'name': 'Premium', 'type': 'Luxury Sedan', 'price': '₹320', 'eta': '6 min', 'capacity': '4', 'icon': Icons.directions_car, 'color': Color(0xFF1C2656), 'image': 'assets/images/texi2.png'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          if (!_locationConfirmed)
            Container(
              color: Theme.of(context).cardColor,
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.arrow_back, size: 20),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _showLocationInputs = true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).cardColor,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey[300]!),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${_pickupController.text} → ${_dropController.text}',
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(Icons.edit, size: 16, color: Colors.grey[600]),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_showLocationInputs)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Column(
                          children: [
                            _buildLocationInput(Icons.radio_button_checked, _pickupController, Color(0xFF4CAF50), 'Current Location'),
                            Padding(
                              padding: const EdgeInsets.only(left: 10),
                              child: Row(
                                children: [
                                  Column(
                                    children: List.generate(2, (index) => Container(
                                      margin: const EdgeInsets.symmetric(vertical: 1),
                                      width: 2,
                                      height: 3,
                                      color: Colors.grey[400],
                                    )),
                                  ),
                                ],
                              ),
                            ),
                            _buildLocationInput(Icons.location_on, _dropController, Color(0xFFFF5252), 'Select destination'),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () {
                                  if (_dropController.text.isNotEmpty && _dropController.text != 'Select Destination') {
                                    setState(() {
                                      _showLocationInputs = false;
                                      _locationConfirmed = true;
                                    });
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Color(0xFF1C2656),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text('Confirm Location', style: TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(28.6139, 77.2090),
                    initialZoom: 13.0,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.goracabs.customer',
                    ),
                    if (_isTaxiComing)
                      PolylineLayer(
                        polylines: [
                          if (!_showFullTripMap)
                            Polyline(
                              points: [
                                LatLng(28.6220, 77.2150), // Mock driver location
                                LatLng(28.6139, 77.2090), // Pickup location
                              ],
                              color: const Color(0xFF1C2656),
                              strokeWidth: 4,
                            ),
                          if (_showFullTripMap)
                            Polyline(
                              points: [
                                LatLng(28.6139, 77.2090), // Pickup location
                                LatLng(28.6200, 77.2300), // Mock drop location
                              ],
                              color: const Color(0xFF4CAF50),
                              strokeWidth: 4,
                            ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        if (!_showFullTripMap)
                          Marker(
                            point: LatLng(28.6139, 77.2090),
                            width: 40,
                            height: 40,
                            child: const Icon(Icons.location_on, color: Color(0xFFFF5252), size: 40),
                          ),
                        if (_showFullTripMap)
                          Marker(
                            point: LatLng(28.6200, 77.2300), // Mock drop location
                            width: 45,
                            height: 45,
                            child: const Icon(Icons.location_on, color: Colors.green, size: 45),
                          ),
                        // Show economy car markers when Cab Economy is selected
                        if (_selectedVehicle == 'Cab Economy' && !_isTaxiComing)
                          ..._economyLocations.asMap().entries.map((entry) {
                            final index = entry.key;
                            final location = entry.value;
                            final rotationAngle = (index * 90.0) * (3.14159 / 180);
                            
                            return Marker(
                              point: location,
                              width: 50,
                              height: 50,
                              child: Transform.rotate(
                                angle: rotationAngle,
                                child: Image.asset(
                                  'assets/images/topview/economy-top.png',
                                  width: 50,
                                  height: 50,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      width: 50,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        color: Color(0xFF1C2656),
                                        borderRadius: BorderRadius.circular(25),
                                      ),
                                      child: const Icon(
                                        Icons.directions_car,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            );
                          }).toList(),
                        // Show SUV markers when SUV is selected
                        if (_selectedVehicle == 'SUV' && !_isTaxiComing)
                          ..._suvLocations.asMap().entries.map((entry) {
                            final index = entry.key;
                            final location = entry.value;
                            final rotationAngle = (index * 180.0) * (3.14159 / 180);
                            
                            return Marker(
                              point: location,
                              width: 50,
                              height: 50,
                              child: Transform.rotate(
                                angle: rotationAngle,
                                child: Image.asset(
                                  'assets/images/topview/suv-top.png',
                                  width: 50,
                                  height: 50,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      width: 50,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        color: Color(0xFF1C2656),
                                        borderRadius: BorderRadius.circular(25),
                                      ),
                                      child: const Icon(
                                        Icons.airport_shuttle,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            );
                          }).toList(),
                        // Show premium car markers when Premium is selected
                        if (_selectedVehicle == 'Premium' && !_isTaxiComing)
                          ..._premiumLocations.asMap().entries.map((entry) {
                            final index = entry.key;
                            final location = entry.value;
                            final rotationAngle = (index * 45.0) * (3.14159 / 180);
                            
                            return Marker(
                              point: location,
                              width: 50,
                              height: 50,
                              child: Transform.rotate(
                                angle: rotationAngle,
                                child: Image.asset(
                                  'assets/images/topview/primium-top.png',
                                  width: 50,
                                  height: 50,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      width: 50,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        color: Color(0xFF1C2656),
                                        borderRadius: BorderRadius.circular(25),
                                      ),
                                      child: const Icon(
                                        Icons.directions_car,
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            );
                          }).toList(),
                        
                        // Show coming taxi marker when tracking is active
                        if (_isTaxiComing && _comingTaxiLocation != null && !_showFullTripMap)
                          Marker(
                            point: _comingTaxiLocation!,
                            width: 60,
                            height: 60,
                            child: Image.asset(
                              _selectedVehicle == 'SUV'
                                  ? 'assets/images/topview/suv-top.png'
                                  : _selectedVehicle == 'Premium'
                                      ? 'assets/images/topview/primium-top.png'
                                      : 'assets/images/topview/economy-top.png',
                              width: 60,
                              height: 60,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) => Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1C2656),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                                ),
                                child: Icon(
                                  _vehicles.firstWhere((v) => v['name'] == _selectedVehicle)['icon'] as IconData,
                                  color: Colors.white,
                                  size: 30,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                if (_showFullTripMap)
                  Positioned(
                    top: 16,
                    left: 16,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
                          ],
                        ),
                        child: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface, size: 24),
                      ),
                    ),
                  ),
                if (_showFullTripMap || _showArrivingButtons)
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Column(
                      children: [
                        FloatingActionButton.small(
                          heroTag: 'support_btn_map_mini',
                          onPressed: () {},
                          backgroundColor: Theme.of(context).cardColor,
                          child: Icon(Icons.support_agent, color: Theme.of(context).colorScheme.onSurface),
                        ),
                        const SizedBox(height: 12),
                        FloatingActionButton.small(
                          heroTag: 'share_btn_map_mini',
                          onPressed: () {},
                          backgroundColor: Theme.of(context).cardColor,
                          child: Icon(Icons.share, color: Theme.of(context).colorScheme.onSurface),
                        ),
                      ],
                    ),
                  ),
                if (!_showFullTripMap && !_showWaitingPopup)
                  DraggableScrollableSheet(
                    initialChildSize: _showPickupConfirmation ? 0.85 : 0.4,
                    minChildSize: _showPickupConfirmation ? 0.4 : 0.4,
                    maxChildSize: _showPickupConfirmation ? 0.85 : 0.4,
                    builder: (context, scrollController) {
                      return Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 10,
                              offset: Offset(0, -2),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Container(
                              margin: const EdgeInsets.symmetric(vertical: 12),
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.grey[300],
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            Expanded(
                              child: ListView(
                                controller: scrollController,
                                physics: _showPickupConfirmation ? null : const NeverScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                                children: [
                                  if (_showPickupConfirmation) ...[
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text('Mini', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                                              SizedBox(height: 8),
                                              Text(
                                                'A regular comfortable hatchback that becomes your everyday ride',
                                                style: TextStyle(fontSize: 14, color: Colors.grey, height: 1.4),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Image.asset(
                                          'assets/images/economy.png',
                                          width: 100,
                                          height: 80,
                                          fit: BoxFit.contain,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 20),
                                    const Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                                      children: [
                                        Column(
                                          children: [
                                            Icon(Icons.directions_car, color: Colors.grey, size: 28),
                                            SizedBox(height: 4),
                                            Text('Comfy Hatch', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                          ],
                                        ),
                                        Column(
                                          children: [
                                            Icon(Icons.account_balance_wallet_outlined, color: Colors.grey, size: 28),
                                            SizedBox(height: 4),
                                            Text('Pocket Friendly', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                          ],
                                        ),
                                        Column(
                                          children: [
                                            Icon(Icons.flash_on, color: Colors.grey, size: 28),
                                            SizedBox(height: 4),
                                            Text('Cashless Rides', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 24),
                                    const Text('Our fleet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Image.asset('assets/images/economy.png', width: 60, height: 45, fit: BoxFit.contain),
                                        const SizedBox(width: 8),
                                        Image.asset('assets/images/auto.jpg', width: 60, height: 45, fit: BoxFit.contain),
                                        const SizedBox(width: 8),
                                        Image.asset('assets/images/texi2.png', width: 60, height: 45, fit: BoxFit.contain),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Maruti Suzuki WagonR, Maruti Suzuki S-Presso, Maruti Suzuki Celerio, Tata Indica',
                                      style: TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                    const SizedBox(height: 24),
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).cardColor,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.grey[200]!),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              const Text('Estimated fare', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                              const Text('₹9930', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          const Text('274 km, 2 day 14 hour', style: TextStyle(fontSize: 13, color: Colors.grey)),
                                          const Divider(height: 24),
                                          _buildFareRow('Base fare @ ₹13/km', '₹8580'),
                                          const SizedBox(height: 8),
                                          _buildFareRow('Driver allowance', '₹600'),
                                          const SizedBox(height: 8),
                                          _buildFareRow('Night time allowance', '₹750'),
                                          const SizedBox(height: 8),
                                          _buildFareRow('Taxes', '₹0'),
                                          const SizedBox(height: 12),
                                          Text(
                                            'Excludes toll costs, parking, permits and state tax\n₹127/hr will be charged for additional hours\n₹13/km will be charged for extra km\nDriver allowance per 24 hours - ₹200\nNight time allowance (11:00 PM - 06:00 AM) - ₹250/night\nExtra fare may apply if you don\'t end trip at Jodhpur',
                                            style: TextStyle(fontSize: 11, color: Colors.grey[600], height: 1.4),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ] else ...[
                                    const Text('Select Vehicle', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                  ],
                                  const SizedBox(height: 16),
                                  if (!_showPickupConfirmation) ...[
                                    ..._vehicles.map((v) => _buildVehicleCard(v)),
                                    const SizedBox(height: 80),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
          if (!_showFullTripMap && !_showWaitingPopup)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                boxShadow: [BoxShadow(color: Colors.black.withAlpha(15), blurRadius: 10, offset: const Offset(0, -2))],
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _selectedVehicle == null ? null : () {
                      setState(() {
                        _locationConfirmed = true; // Ensure header is hidden when booking starts
                      });
                      if (_showPickupConfirmation) {
                        setState(() {
                          _showWaitingPopup = true;
                          _locationConfirmed = true; // Ensure header is hidden when booking starts
                        });
                        // Show final waiting popup directly
                        _showFinalWaitingDialog();
                      } else {
                        setState(() {
                          _showPickupConfirmation = true;
                        });
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1C2656),
                      disabledBackgroundColor: Colors.grey[300],
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      _selectedVehicle == null ? 'Select a vehicle' : _showPickupConfirmation ? 'Done' : 'Book Now',
                      style: TextStyle(
                        fontSize: 16,
                        color: _selectedVehicle == null ? Colors.grey[600] : Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLocationInput(IconData icon, TextEditingController controller, Color iconColor, String hint) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                hintStyle: TextStyle(color: Colors.grey[400], fontSize: 15),
              ),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleCard(Map<String, dynamic> v) {
    final isSelected = _selectedVehicle == v['name'];
    return GestureDetector(
      onTap: () => setState(() => _selectedVehicle = v['name']),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? (v['color'] as Color).withOpacity(0.05) : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? (v['color'] as Color) : Colors.grey[300]!, 
            width: isSelected ? 2 : 1
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: (v['color'] as Color).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  v['image'],
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(v['icon'], color: v['color'] as Color, size: 24);
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(v['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text('${v['type']} • ${v['capacity']} seats', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(v['price'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF4CAF50))),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Color(0xFF4CAF50).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(v['eta'], style: const TextStyle(fontSize: 10, color: Color(0xFF4CAF50), fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFareRow(String label, String amount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        Text(amount, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    );
  }

  void _showFinalWaitingDialog() {
    final selectedVehicleData = _vehicles.firstWhere((v) => v['name'] == _selectedVehicle);
    final basePrice = int.parse(selectedVehicleData['price'].replaceAll('₹', ''));
    final totalPrice = _selectedTip != null ? basePrice + _selectedTip! : basePrice;
    
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        // Auto-close after 3 seconds and show driver details
        Future.delayed(const Duration(seconds: 3), () {
          if (Navigator.canPop(context)) {
            Navigator.of(context).pop();
            _showDriverArrivingDialog();
          }
        });

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1C2656)),
              ),
              const SizedBox(height: 16),
              const Text(
                'Please Wait',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _selectedTip != null 
                    ? 'Tip added! Finding your driver...'
                    : 'Finding your driver...',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Base Fare:',
                          style: TextStyle(fontSize: 14),
                        ),
                        Text(
                          selectedVehicleData['price'],
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    if (_selectedTip != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Tip:',
                            style: TextStyle(fontSize: 14),
                          ),
                          Text(
                            '+₹$_selectedTip',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.green),
                          ),
                        ],
                      ),
                      const Divider(height: 12),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Fare:',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '₹$totalPrice',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _showCancelReasonDialog(),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text(
                        'Cancel Booking',
                        style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[400],
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text(
                        'Searching...',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  void _showDriverArrivingDialog() {
    final selectedVehicleData = _vehicles.firstWhere((v) => v['name'] == _selectedVehicle);
    
    // Start tracking on map
    setState(() {
      _isTaxiComing = true;
      _showArrivingButtons = true;
      // Set a mock location for the coming taxi (nearby)
      _comingTaxiLocation = LatLng(28.6220, 77.2150);
    });
    
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent, // Don't dim the map
      builder: (BuildContext context) {
        // Auto-close after 5 seconds and show full map
        Future.delayed(const Duration(seconds: 5), () {
          if (Navigator.canPop(context)) {
            Navigator.of(context).pop();
            setState(() {
              _showFullTripMap = true;
              _showArrivingButtons = false;
            });
            // Start simulation for ride ending after another 5 seconds
            Future.delayed(const Duration(seconds: 5), () {
              _showRideCompletedDialog();
            });
          }
        });

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -2)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Your ride is on the way',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  const Text('Ride PIN: ', style: TextStyle(fontSize: 16, color: Colors.grey)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: const Text(
                      '4829',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2, color: Colors.black),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // ETA and Distance Info
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.access_time_filled, color: Color(0xFF1C2656), size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Arriving in 4 mins',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                    ),
                    const SizedBox(width: 12),
                    Container(width: 1, height: 15, color: Colors.grey[300]),
                    const SizedBox(width: 12),
                    const Icon(Icons.location_on, color: Colors.green, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      '1.2 km away',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              
              // Driver Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[200]!),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: Row(
                  children: [
                    // Driver Profile Image (Now on the left)
                    Container(
                      width: 55,
                      height: 55,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey[200]!, width: 2),
                        image: const DecorationImage(
                          image: NetworkImage('https://i.pravatar.cc/150?u=rajesh'),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Driver Details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Rajesh Kumar',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                          ),
                          const SizedBox(height: 4),
                          const Row(
                            children: [
                              Icon(Icons.star, color: Colors.amber, size: 16),
                              SizedBox(width: 4),
                              Text('4.9 (1.2k+ rides)', style: TextStyle(fontSize: 13, color: Colors.grey)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'White Swift Dzire • DL 01 AB 1234',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    // Vehicle Image (Now on the right and larger)
                    SizedBox(
                      width: 90,
                      height: 70,
                      child: Image.asset(
                        selectedVehicleData['image'],
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          selectedVehicleData['icon'], 
                          color: selectedVehicleData['color'],
                          size: 40,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 12),
              
              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.call, color: Colors.green),
                      label: Text('Call', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).cardColor,
                        foregroundColor: Theme.of(context).colorScheme.onSurface,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey[200]!),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.message, color: Color(0xFF1C2656)),
                      label: Text('Message', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).cardColor,
                        foregroundColor: Theme.of(context).colorScheme.onSurface,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey[200]!),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    setState(() {
                      _showArrivingButtons = false;
                    });
                    _showCancelReasonDialog();
                  },
                  child: const Text('Cancel Ride', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600, fontSize: 15)),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  void _showCancelReasonDialog() {
    final List<String> reasons = [
      'Plan changed',
      'Driver is too far',
      'Found another ride',
      'Wait time is too long',
      'Wrong location selected',
      'Other'
    ];
    String? selectedReason;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const Text(
                    'Cancel Ride',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Please select a reason for cancellation',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  ...reasons.map((reason) => RadioListTile<String>(
                    title: Text(reason, style: const TextStyle(fontSize: 15)),
                    value: reason,
                    groupValue: selectedReason,
                    activeColor: const Color(0xFF1C2656),
                    contentPadding: EdgeInsets.zero,
                    onChanged: (value) {
                      setDialogState(() {
                        selectedReason = value;
                      });
                    },
                  )),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: selectedReason == null ? null : () {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (context) => const HomeScreen()),
                          (route) => false,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1C2656),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text(
                        'Confirm Cancellation',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Back', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showRideCompletedDialog() {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 64),
              const SizedBox(height: 16),
              const Text(
                'Ride Completed!',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'You have reached your destination safely.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RatingScreen(
                          driverName: 'Rajesh Kumar',
                          vehicleName: _selectedVehicle!,
                          selectedTip: _selectedTip,
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1C2656),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    'Rate Your Ride',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
