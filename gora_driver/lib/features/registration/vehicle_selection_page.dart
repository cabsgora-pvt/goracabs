import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/app_widgets.dart';
import '../../services/driver_api_service.dart';
import 'vehicle_details_page.dart';

class VehicleSelectionPage extends StatefulWidget {
  static const route = '/registration/vehicle-selection';
  const VehicleSelectionPage({super.key});
  @override
  State<VehicleSelectionPage> createState() => _VehicleSelectionPageState();
}

class _VehicleSelectionPageState extends State<VehicleSelectionPage> {
  List<Map<String, dynamic>> _vehicleTypes = [];
  bool _loading = true;
  Map<String, dynamic>? _selected;

  @override
  void initState() {
    super.initState();
    _loadVehicleTypes();
  }

  Future<void> _loadVehicleTypes() async {
    try {
      final types = await DriverApiService.getVehicleTypes();
      // Filter for taxi-capable vehicles
      final filtered = types.where((t) {
        final services = t['services'] as List?;
        if (services == null) return true; // show all if no filter info
        return services.contains('taxi');
      }).toList();
      if (mounted) setState(() { _vehicleTypes = filtered.isEmpty ? types : filtered; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _next() {
    if (_selected == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a vehicle type')),
      );
      return;
    }
    Navigator.pushNamed(
      context,
      VehicleDetailsPage.route,
      arguments: {'vehicle': _selected},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _vehicleTypes.isEmpty
                    ? Center(child: Text('No vehicle types available', style: TextStyle(color: AppColors.textGrey)))
                    : Column(
                        children: [
                          Expanded(
                            child: GridView.builder(
                              padding: const EdgeInsets.all(16),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 1.1,
                              ),
                              itemCount: _vehicleTypes.length,
                              itemBuilder: (ctx, i) {
                                final vt = _vehicleTypes[i];
                                final vtId = (vt['_id'] ?? vt['id'] ?? '').toString();
                                final selId = (_selected?['_id'] ?? _selected?['id'] ?? '').toString();
                                final isSelected = vtId.isNotEmpty && vtId == selId;
                                return GestureDetector(
                                  onTap: () => setState(() => _selected = vt),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: isSelected ? AppColors.primary : AppColors.divider,
                                        width: isSelected ? 2.5 : 1.5,
                                      ),
                                      boxShadow: isSelected
                                          ? [BoxShadow(color: AppColors.primary.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 4))]
                                          : [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4)],
                                    ),
                                    child: Stack(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Builder(builder: (_) {
                                                final raw = (vt['imageUrl'] as String? ?? '').trim();
                                                final imgUrl = raw.isEmpty ? '' : AppConfig.imageUrl(raw);
                                                return imgUrl.isNotEmpty
                                                    ? Image.network(
                                                        imgUrl,
                                                        height: 60,
                                                        width: double.infinity,
                                                        fit: BoxFit.contain,
                                                        errorBuilder: (_, __, ___) => Icon(Icons.directions_car_rounded, size: 48, color: isSelected ? AppColors.primary : AppColors.textGrey),
                                                      )
                                                    : Icon(Icons.directions_car_rounded, size: 52, color: isSelected ? AppColors.primary : AppColors.textGrey);
                                              }),
                                              const SizedBox(height: 8),
                                              Text(
                                                vt['name'] as String? ?? '',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 13,
                                                  color: isSelected ? AppColors.primary : AppColors.textDark,
                                                ),
                                                textAlign: TextAlign.center,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Selected checkmark badge
                                        if (isSelected)
                                          Positioned(
                                            top: 6, right: 6,
                                            child: Container(
                                              padding: const EdgeInsets.all(2),
                                              decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                                              child: const Icon(Icons.check_rounded, size: 14, color: Colors.white),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            child: PrimaryButton(label: 'Next', onTap: _next),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Select Vehicle Type',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Step 2 of 3 — Choose your vehicle category',
                  style: TextStyle(fontSize: 13, color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
