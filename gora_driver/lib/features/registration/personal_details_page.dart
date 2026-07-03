import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/app_colors.dart';
import '../../core/widgets/app_widgets.dart';
import '../../services/driver_api_service.dart';
import 'vehicle_selection_page.dart';

const _indianStates = [
  'Andhra Pradesh', 'Arunachal Pradesh', 'Assam', 'Bihar', 'Chhattisgarh',
  'Goa', 'Gujarat', 'Haryana', 'Himachal Pradesh', 'Jharkhand', 'Karnataka',
  'Kerala', 'Madhya Pradesh', 'Maharashtra', 'Manipur', 'Meghalaya', 'Mizoram',
  'Nagaland', 'Odisha', 'Punjab', 'Rajasthan', 'Sikkim', 'Tamil Nadu',
  'Telangana', 'Tripura', 'Uttar Pradesh', 'Uttarakhand', 'West Bengal',
  'Delhi', 'Jammu & Kashmir', 'Ladakh', 'Puducherry', 'Chandigarh',
];

class PersonalDetailsPage extends StatefulWidget {
  static const route = '/registration/personal';
  const PersonalDetailsPage({super.key});
  @override
  State<PersonalDetailsPage> createState() => _PersonalDetailsPageState();
}

class _PersonalDetailsPageState extends State<PersonalDetailsPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _referralController = TextEditingController();
  String? _selectedState;
  String? _selectedZoneId;
  String? _selectedZoneName;
  List<Map<String, dynamic>> _zones = [];
  bool _loading = false;
  bool _zonesLoading = true;
  late String _phone;
  XFile? _profilePhoto;
  Uint8List? _profilePhotoBytes;
  String _profilePicUrl = '';
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadZones();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    _phone = args?['phone'] as String? ?? '';
    // Pre-fill if resubmitting
    final driver = args?['driver'] as Map?;
    if (driver != null) {
      _name.text = driver['name'] as String? ?? '';
      _email.text = driver['email'] as String? ?? '';
      _selectedState = driver['state'] as String?;
      _selectedZoneId = driver['zoneId'] as String?;
      _selectedZoneName = driver['zoneName'] as String?;
    }
  }

  Future<void> _loadZones() async {
    try {
      final zones = await DriverApiService.getZones();
      if (mounted) setState(() { _zones = zones; _zonesLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _zonesLoading = false);
    }
  }

  Future<void> _pickPhoto() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() { _profilePhoto = picked; _profilePhotoBytes = bytes; });
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (_selectedState == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a state')));
      return;
    }
    if (_selectedZoneId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a zone')));
      return;
    }
    setState(() => _loading = true);
    try {
      // Upload profile pic if selected
      if (_profilePhoto != null && _profilePicUrl.isEmpty) {
        final url = await DriverApiService.uploadFile(_profilePhoto!);
        _profilePicUrl = url ?? '';
      }
      final res = await DriverApiService.savePersonal({
        'name': _name.text.trim(),
        'email': _email.text.trim(),
        'state': _selectedState,
        'zoneId': _selectedZoneId,
        'zoneName': _selectedZoneName,
        'profilePicUrl': _profilePicUrl,
        'referralCode': _referralController.text.trim().toUpperCase(),
      });
      if (!mounted) return;
      if (res['error'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['error'].toString()), backgroundColor: AppColors.red));
      } else {
        Navigator.pushNamed(
          context,
          VehicleSelectionPage.route,
          arguments: {'zoneId': _selectedZoneId, 'zoneName': _selectedZoneName},
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.red));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _referralController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    _stepIndicator(1),
                    const SizedBox(height: 24),

                    // ── Profile photo picker ──
                    Center(
                      child: GestureDetector(
                        onTap: _pickPhoto,
                        child: Stack(
                          children: [
                            Container(
                              width: 100, height: 100,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.cardBg,
                                border: Border.all(color: AppColors.primary.withAlpha(80), width: 3),
                              ),
                              child: ClipOval(
                                child: _profilePhotoBytes != null
                                    ? Image.memory(_profilePhotoBytes!, fit: BoxFit.cover)
                                    : const Icon(Icons.person_rounded, size: 52, color: AppColors.primary),
                              ),
                            ),
                            Positioned(
                              bottom: 0, right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(7),
                                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                                child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 16),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: Text('Upload Profile Photo', style: TextStyle(fontSize: 12, color: AppColors.textGrey)),
                    ),
                    const SizedBox(height: 20),

                    TextFormField(
                      controller: _name,
                      decoration: const InputDecoration(
                        labelText: 'Full Name *',
                        prefixIcon: Icon(Icons.person_rounded, color: AppColors.primary),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Full name is required' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      readOnly: true,
                      initialValue: '+91 $_phone',
                      decoration: InputDecoration(
                        labelText: 'Mobile Number',
                        prefixIcon: Icon(Icons.phone_rounded, color: AppColors.textGrey),
                      ),
                      style: TextStyle(color: AppColors.textGrey),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email Address',
                        prefixIcon: Icon(Icons.email_rounded, color: AppColors.primary),
                      ),
                      validator: (v) {
                        if (v != null && v.isNotEmpty && !v.contains('@')) return 'Enter valid email';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _referralController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Referral code (optional)',
                        hintText: "Enter a friend's code",
                        prefixIcon: Icon(Icons.card_giftcard_rounded, color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _selectedState,
                      decoration: const InputDecoration(
                        labelText: 'State *',
                        prefixIcon: Icon(Icons.map_rounded, color: AppColors.primary),
                      ),
                      items: _indianStates.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                      onChanged: (v) => setState(() => _selectedState = v),
                    ),
                    const SizedBox(height: 16),
                    _zonesLoading
                        ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                        : DropdownButtonFormField<String>(
                            value: _selectedZoneId,
                            decoration: const InputDecoration(
                              labelText: 'Zone *',
                              prefixIcon: Icon(Icons.location_city_rounded, color: AppColors.primary),
                            ),
                            items: _zones.map((z) => DropdownMenuItem(
                              value: z['_id'] as String? ?? z['id'] as String?,
                              child: Text(z['name'] as String? ?? ''),
                            )).toList(),
                            onChanged: (v) {
                              final zone = _zones.firstWhere(
                                (z) => (z['_id'] ?? z['id']) == v,
                                orElse: () => {},
                              );
                              setState(() {
                                _selectedZoneId = v;
                                _selectedZoneName = zone['name'] as String?;
                              });
                            },
                          ),
                    const SizedBox(height: 32),
                    PrimaryButton(label: 'Continue', loading: _loading, onTap: _submit),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
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
                  'Personal Details',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Step 1 of 3 — Tell us about yourself',
                  style: TextStyle(fontSize: 13, color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepIndicator(int current) {
    return Row(
      children: List.generate(3, (i) => Expanded(
        child: Container(
          height: 4,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: i < current ? AppColors.primary : AppColors.divider,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      )),
    );
  }
}
