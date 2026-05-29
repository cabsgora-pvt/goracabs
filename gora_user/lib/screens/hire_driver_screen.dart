import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'hire_driver_booking_details_screen.dart';
import 'home_screen.dart';
import 'rating_screen.dart';

class HireDriverScreen extends StatefulWidget {
  const HireDriverScreen({super.key});

  @override
  State<HireDriverScreen> createState() => _HireDriverScreenState();
}

class _HireDriverScreenState extends State<HireDriverScreen> {
  String _hireDuration = 'Hourly';
  String _tripType = 'One Way';
  String _transmissionType = 'Manual';
  String? _selectedVehicle;
  final _pickupController = TextEditingController();
  final _dropController = TextEditingController();
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  DateTime? _returnDate;
  TimeOfDay? _returnTime;
  int _selectedHours = 4;
  int _selectedDays = 1;
  bool _isSearching = false;
  bool _driverAssigned = false;

  final List<Map<String, dynamic>> _vehicles = [
    {'name': 'Sedan', 'type': 'Spacious', 'capacity': '4', 'icon': Icons.directions_car, 'color': Color(0xFF9C27B0), 'image': 'assets/images/texi2.png'},
    {'name': 'SUV', 'type': 'Premium', 'capacity': '6', 'icon': Icons.airport_shuttle, 'color': Color(0xFF4CAF50), 'image': 'assets/images/texi.png'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Hire Driver'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          color: Colors.black87,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Trip Type Selection
                  const Text('Trip Type', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _buildSelectButton('One Way', _tripType, (val) => setState(() => _tripType = val))),
                      const SizedBox(width: 12),
                      Expanded(child: _buildSelectButton('Round Trip', _tripType, (val) => setState(() => _tripType = val))),
                    ],
                  ),
                  const SizedBox(height: 20),

                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      children: [
                        _buildLocationRow(Icons.radio_button_checked, const Color(0xFF4CAF50), _pickupController, 'Enter pickup location'),
                        _buildDivider(),
                        _buildLocationRow(Icons.location_on, const Color(0xFFFF5252), _dropController, 'Enter drop location'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  const Text('Schedule', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  _buildDateTimePicker(
                    'Pickup',
                    _selectedDate,
                    _selectedTime,
                    (d) => setState(() => _selectedDate = d),
                    (t) => setState(() => _selectedTime = t),
                  ),
                  
                  if (_tripType == 'Round Trip') ...[
                    const SizedBox(height: 12),
                    _buildDateTimePicker(
                      'Return',
                      _returnDate,
                      _returnTime,
                      (d) => setState(() => _returnDate = d),
                      (t) => setState(() => _returnTime = t),
                    ),
                  ],

                  const SizedBox(height: 20),
                  const Text('Hire Mode', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _buildSelectButton('Hourly', _hireDuration, (val) => setState(() => _hireDuration = val))),
                      const SizedBox(width: 12),
                      Expanded(child: _buildSelectButton('Daily', _hireDuration, (val) => setState(() => _hireDuration = val))),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text('Select ${_hireDuration == 'Hourly' ? 'Hours' : 'Days'}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _buildDurationSelector(),
                  const SizedBox(height: 12),
                  _buildPriceDisplay(),
                  const SizedBox(height: 20),

                  const Text('Car Transmission', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _buildSelectButton('Manual', _transmissionType, (val) => setState(() => _transmissionType = val))),
                      const SizedBox(width: 12),
                      Expanded(child: _buildSelectButton('Automatic', _transmissionType, (val) => setState(() => _transmissionType = val))),
                    ],
                  ),

                  const SizedBox(height: 20),
                  const Text('Select Your Vehicle Type', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 2.5,
                    ),
                    itemCount: _vehicles.length,
                    itemBuilder: (context, index) => _buildVehicleCard(_vehicles[index]),
                  ),
                  const SizedBox(height: 20),
                  const Text('Trip Conditions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      children: [
                        _buildConditionItem(Icons.person, 'Verified professional driver'),
                        const SizedBox(height: 8),
                        _buildConditionItem(Icons.fastfood_outlined, 'Food charge extra for > 4 hour package'),
                        const SizedBox(height: 8),
                        _buildConditionItem(Icons.nightlight_round, 'Night drive extra charges (10 PM - 6 AM)'),
                        const SizedBox(height: 8),
                        _buildConditionItem(Icons.toll, 'Tolls & parking extra (pay directly)'),
                        const SizedBox(height: 8),
                        _buildConditionItem(Icons.schedule, 'Overtime: ₹150/hour extra'),
                        const SizedBox(height: 8),
                        _buildConditionItem(Icons.info_outline, 'Driver will drive your own car'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withAlpha(15), blurRadius: 10, offset: const Offset(0, -2))],
            ),
            child: ElevatedButton(
              onPressed: _selectedVehicle == null ? null : () {
                _showBookingConfirmationDialog();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2196F3),
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                _selectedVehicle == null 
                    ? 'Complete Selection' 
                    : 'Confirm Hire Driver',
                style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectButton(String label, String groupValue, Function(String) onChanged) {
    final isSelected = groupValue == label;
    return GestureDetector(
      onTap: () => onChanged(label),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2196F3) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? const Color(0xFF2196F3) : Colors.grey[300]!),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateTimePicker(String label, DateTime? date, TimeOfDay? time, Function(DateTime) onDate, Function(TimeOfDay) onTime) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (d != null) onDate(d);
            },
            icon: const Icon(Icons.calendar_today, size: 18),
            label: Text(date == null ? '$label Date' : '${date.day}/${date.month}/${date.year}'),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
              if (t != null) onTime(t);
            },
            icon: const Icon(Icons.access_time, size: 18),
            label: Text(time == null ? '$label Time' : time.format(context)),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
        ),
      ],
    );
  }

  Widget _buildLocationRow(IconData icon, Color color, TextEditingController controller, String hint) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 40,
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.only(left: 9, top: 4, bottom: 4),
      child: Row(
        children: [
          Column(
            children: List.generate(2, (index) => Container(
              margin: const EdgeInsets.symmetric(vertical: 1),
              width: 2,
              height: 3,
              decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(1)),
            )),
          ),
        ],
      ),
    );
  }

  Widget _buildDurationSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('$_hireDuration Selection', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          Row(
            children: [
              _buildRoundButton(Icons.remove, () {
                setState(() {
                  if (_hireDuration == 'Hourly') { if (_selectedHours > 1) _selectedHours--; }
                  else { if (_selectedDays > 1) _selectedDays--; }
                });
              }),
              const SizedBox(width: 20),
              Text(_hireDuration == 'Hourly' ? '$_selectedHours hr' : '$_selectedDays day', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(width: 20),
              _buildRoundButton(Icons.add, () {
                setState(() {
                  if (_hireDuration == 'Hourly') { if (_selectedHours < 24) _selectedHours++; }
                  else { if (_selectedDays < 30) _selectedDays++; }
                });
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPriceDisplay() {
    final price = _hireDuration == 'Hourly' ? _selectedHours * 150 : _selectedDays * 1500;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2196F3).withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2196F3).withOpacity(0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Estimated Price', style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text(_hireDuration == 'Hourly' ? '₹150/hour' : '₹1500/day', style: TextStyle(fontSize: 12, color: Colors.blue[700], fontWeight: FontWeight.w600)),
            ],
          ),
          Text('₹$price', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF2196F3))),
        ],
      ),
    );
  }

  Widget _buildRoundButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.grey[300]!),
          boxShadow: [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Icon(icon, size: 20, color: const Color(0xFF2196F3)),
      ),
    );
  }

  Widget _buildVehicleCard(Map<String, dynamic> v) {
    final isSelected = _selectedVehicle == v['name'];
    return GestureDetector(
      onTap: () => setState(() => _selectedVehicle = v['name']),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? (v['color'] as Color) : Colors.grey[300]!, width: isSelected ? 2 : 1),
        ),
        child: Row(
          children: [
            SizedBox(width: 60, height: 45, child: Image.asset(v['image'], fit: BoxFit.contain, errorBuilder: (context, error, stackTrace) => Icon(v['icon'], color: v['color'] as Color, size: 24))),
            const SizedBox(width: 10),
            Expanded(child: Text(v['name'], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
          ],
        ),
      ),
    );
  }

  Widget _buildConditionItem(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
      ],
    );
  }

  void _showBookingConfirmationDialog() {
    final selectedVehicleData = _vehicles.firstWhere((v) => v['name'] == _selectedVehicle);
    final duration = _hireDuration == 'Hourly' ? '$_selectedHours Hours' : '$_selectedDays Day(s)';
    final basePrice = _hireDuration == 'Hourly' ? _selectedHours * 150 : _selectedDays * 1500;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(margin: const EdgeInsets.symmetric(vertical: 12), width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Confirm Hire', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                              SizedBox(height: 8),
                              Text('Professional verified drivers for your personal vehicle', style: TextStyle(fontSize: 14, color: Colors.grey, height: 1.4)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Image.asset(selectedVehicleData['image'], width: 100, height: 80, fit: BoxFit.contain, errorBuilder: (context, error, stackTrace) => const Icon(Icons.person, size: 60, color: Color(0xFF2196F3))),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _FeatureIcon(icon: Icons.verified_user, label: 'Verified Pro'),
                        _FeatureIcon(icon: Icons.security, label: 'Safe Ride'),
                        _FeatureIcon(icon: Icons.timer, label: 'Punctual'),
                      ],
                    ),
                    const SizedBox(height: 32),
                    const Text('Booking Summary', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[200]!)),
                      child: Column(
                        children: [
                          _buildMinimalConfirmRow(Icons.alt_route, const Color(0xFF2196F3), 'Trip Type', _tripType),
                          const Divider(height: 24),
                          _buildMinimalConfirmRow(Icons.radio_button_checked, const Color(0xFF4CAF50), 'Pickup', _pickupController.text.isEmpty ? 'Current Location' : _pickupController.text),
                          const Padding(padding: EdgeInsets.only(left: 10), child: Align(alignment: Alignment.centerLeft, child: SizedBox(height: 10, child: VerticalDivider(width: 2)))),
                          _buildMinimalConfirmRow(Icons.calendar_today, const Color(0xFF2196F3), 'Start', '${_selectedDate == null ? 'Today' : '${_selectedDate!.day}/${_selectedDate!.month}'} at ${_selectedTime == null ? 'Now' : _selectedTime!.format(context)}'),
                          if (_tripType == 'Round Trip') ...[
                            const Padding(padding: EdgeInsets.only(left: 10), child: Align(alignment: Alignment.centerLeft, child: SizedBox(height: 10, child: VerticalDivider(width: 2)))),
                            _buildMinimalConfirmRow(Icons.history, Colors.orange, 'Return', '${_returnDate == null ? 'Not set' : '${_returnDate!.day}/${_returnDate!.month}'} at ${_returnTime == null ? 'Not set' : _returnTime!.format(context)}'),
                          ],
                          const Divider(height: 24),
                          _buildMinimalConfirmRow(Icons.settings, Colors.grey, 'Transmission', _transmissionType),
                          const SizedBox(height: 12),
                          _buildMinimalConfirmRow(Icons.directions_car_outlined, Colors.grey, 'Car Type', _selectedVehicle!),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(color: const Color(0xFF2196F3).withOpacity(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF2196F3).withOpacity(0.1))),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Estimated Fare', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              Text('₹$basePrice', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF2196F3))),
                            ],
                          ),
                          const Divider(height: 32),
                          _buildFareRow('Base Driver Fee', '₹$basePrice'),
                          const SizedBox(height: 16),
                          const Text('Tolls, parking and fuel are to be provided by the customer. Overtime charges apply after the package duration.', style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.4)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                              const SizedBox(width: 8),
                              Text('Fare Breakdown', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue[700])),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Base Driver Fee:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                              Text('₹$basePrice', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Duration:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                              Text(duration, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const Divider(height: 24),
                          const Text('Extra Charges (if applicable):', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey)),
                          const SizedBox(height: 12),
                          _buildBulletPoint('Night allowance (11 PM - 6 AM): ₹200'),
                          _buildBulletPoint('Early morning charge (till 6 AM): ₹200'),
                          _buildBulletPoint('Overtime per hour: ₹100'),
                          _buildBulletPoint('Food charges: ₹200 per day'),
                          _buildBulletPoint('Tolls & parking: Pay directly'),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.warning_amber, color: Colors.orange, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'If driver is released at 4 AM, next day charges (₹1500) apply',
                                    style: TextStyle(fontSize: 12, color: Colors.orange[900], fontWeight: FontWeight.w500),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Center(
                            child: InkWell(
                              onTap: () {},
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('View Cancellation Policy', style: TextStyle(color: Colors.blue[700], fontWeight: FontWeight.w500, fontSize: 13)),
                                  const SizedBox(width: 4),
                                  Icon(Icons.arrow_forward_ios, color: Colors.blue[700], size: 12),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 10, offset: const Offset(0, -5))]),
                child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _showFindingDriverDialog();
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2196F3), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: const Text('Confirm Hire', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showFindingDriverDialog() {
    setState(() {
      _isSearching = true;
    });

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        Future.delayed(const Duration(seconds: 3), () {
          if (Navigator.canPop(context)) {
            Navigator.of(context).pop();
            _showDriverAssignedDialog();
          }
        });

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2196F3))),
              SizedBox(height: 16),
              Text('Finding your Driver', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Please wait while we connect you with a nearby professional pilot.', style: TextStyle(fontSize: 14, color: Colors.grey), textAlign: TextAlign.center),
              SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  void _showDriverAssignedDialog() {
    setState(() {
      _isSearching = false;
      _driverAssigned = true;
    });

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -2))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
              const Text('Professional Pilot Assigned', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey[200]!), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]),
                child: Row(
                  children: [
                    Container(width: 55, height: 55, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.grey[200]!, width: 2), image: const DecorationImage(image: NetworkImage('https://i.pravatar.cc/150?u=hiredriver'), fit: BoxFit.cover))),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Manish Verma', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black)), SizedBox(height: 4), Row(children: [Icon(Icons.star, color: Colors.amber, size: 16), SizedBox(width: 4), Text('4.9 (1.8k+ hire trips)', style: TextStyle(fontSize: 13, color: Colors.grey))]), SizedBox(height: 4), Text('Experience: 8+ Years • Verified Pro', style: TextStyle(fontSize: 11, color: Colors.grey))])),
                    Icon(Icons.verified, color: Colors.blue, size: 30),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: ElevatedButton.icon(onPressed: () {}, icon: const Icon(Icons.call, color: Colors.green), label: const Text('Call', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey[200]!)), elevation: 2))),
                  const SizedBox(width: 12),
                  Expanded(child: ElevatedButton.icon(onPressed: () {}, icon: const Icon(Icons.message, color: Color(0xFF2196F3)), label: const Text('Message', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey[200]!)), elevation: 2))),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    final duration = _hireDuration == 'Hourly' ? '$_selectedHours Hours' : '$_selectedDays Day(s)';
                    final basePrice = _hireDuration == 'Hourly' ? _selectedHours * 150 : _selectedDays * 1500;
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => HireDriverBookingDetailsScreen(
                          inquiryId: 'HD${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}',
                          pickupLocation: _pickupController.text.isEmpty ? 'Current Location' : _pickupController.text,
                          dropLocation: _dropController.text.isEmpty ? 'Not Specified' : _dropController.text,
                          carType: '$_selectedVehicle ($_transmissionType)',
                          hireDuration: _hireDuration,
                          package: duration,
                          price: '₹$basePrice',
                          tripStartDate: _selectedDate == null ? 'Today' : '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}',
                          tripTime: _selectedTime == null ? 'Now' : _selectedTime!.format(context),
                          driverName: 'Manish Verma',
                          driverRating: '4.9 (1.8k+ trips)',
                          driverExperience: '8 Years',
                          vehicleNumber: 'DL 03 CD 9876',
                          vehicleModel: 'Honda City',
                          vehicleColor: 'White',
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2196F3),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Booking Details', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              const SizedBox(height: 12),
              Center(child: TextButton(onPressed: () => _showCancelReasonDialog(), child: const Text('Cancel Hire', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600, fontSize: 15)))),
            ],
          ),
        );
      },
    );
  }

  void _showCancelReasonDialog() {
    final List<String> reasons = ['Plan changed', 'Driver is too far', 'Found another option', 'Wait time is too long', 'Wrong details selected', 'Other'];
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
              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
                  const Text('Cancel Hire', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Please select a reason for cancellation', style: TextStyle(fontSize: 14, color: Colors.grey)),
                  const SizedBox(height: 20),
                  ...reasons.map((reason) => RadioListTile<String>(title: Text(reason, style: const TextStyle(fontSize: 15)), value: reason, groupValue: selectedReason, activeColor: const Color(0xFF2196F3), contentPadding: EdgeInsets.zero, onChanged: (value) => setDialogState(() => selectedReason = value))),
                  const SizedBox(height: 24),
                  SizedBox(width: double.infinity, child: ElevatedButton(onPressed: selectedReason == null ? null : () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const HomeScreen()), (route) => false), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2196F3), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('Confirm Cancellation', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)))),
                  const SizedBox(height: 12),
                  Center(child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Back', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)))),
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
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 64),
              const SizedBox(height: 16),
              const Text('Hire Completed!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Your driver service has been completed successfully.', style: TextStyle(fontSize: 14, color: Colors.grey), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => RatingScreen(driverName: 'Manish Verma', vehicleName: 'Driver Service', selectedTip: 0))); }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2196F3), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('Rate Your Driver', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)))),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMinimalConfirmRow(IconData icon, Color color, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        ]),
      ],
    );
  }

  Widget _buildFareRow(String label, String amount) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontSize: 13, color: Colors.black87)),
      Text(amount, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
    ]);
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeatureIcon({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Icon(icon, color: Colors.grey, size: 28),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
    ]);
  }
}
