import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/driver_provider.dart';
import '../../core/constants/app_colors.dart';
import '../../widgets/captain_ui/captain_ui.dart';
import 'widgets/reg_step_scaffold.dart';
import '../../services/driver_api_service.dart';
import 'face_capture_page.dart';

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
  String? _selectedGender;
  String? _selectedZoneId;
  String? _selectedZoneName;
  List<Map<String, dynamic>> _zones = [];
  bool _loading = false;
  bool _zonesLoading = true;
  late String _phone;

  @override
  void initState() {
    super.initState();
    _loadZones();
  }

  bool _prefilled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Once only. didChangeDependencies runs again whenever the route's status
    // changes — e.g. when the State/Zone dropdown menu closes — and re-applying
    // the prefill then reset _selectedState to the driver's old value (or null)
    // while the dropdown still showed the new choice: "Gujarat" on screen,
    // "Please select a state" on Continue.
    if (_prefilled) return;
    _prefilled = true;
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    // Pre-fill if resubmitting
    final driver = args?['driver'] as Map?;
    // A resubmission arrives without 'phone' (only the driver record), which
    // left the locked mobile field reading just "+91".
    _phone = args?['phone'] as String? ??
        (driver?['phone'] ?? '').toString();
    if (_phone.isEmpty) {
      try { _phone = Provider.of<DriverProvider>(context, listen: false).phone; } catch (_) {}
    }
    if (driver != null) {
      _name.text = driver['name'] as String? ?? '';
      _email.text = driver['email'] as String? ?? '';
      // Only values the dropdowns actually offer: a value missing from the
      // items fails Flutter's dropdown assertion, and one shown but not bound
      // is exactly the "select a state" trap.
      final st = (driver['state'] ?? '').toString().trim().toLowerCase();
      _selectedState = _indianStates.where((x) => x.toLowerCase() == st).firstOrNull;
      final g = (driver['gender'] ?? '').toString();
      _selectedGender = const ['female', 'male', 'other'].contains(g) ? g : null;
      _selectedZoneId = driver['zoneId'] as String?;
      _selectedZoneName = driver['zoneName'] as String?;
    }
  }

  Future<void> _loadZones() async {
    try {
      final zones = await DriverApiService.getZones();
      if (mounted) {
        setState(() {
          _zones = zones;
          _zonesLoading = false;
          // A prefilled zone that no longer exists is not a selection.
          if (_selectedZoneId != null && !zones.any((z) => (z['_id'] ?? z['id']) == _selectedZoneId)) {
            _selectedZoneId = null;
            _selectedZoneName = null;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _zonesLoading = false);
    }
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
      final res = await DriverApiService.savePersonal({
        'name': _name.text.trim(),
        'email': _email.text.trim(),
        'state': _selectedState,
        'zoneId': _selectedZoneId,
        'zoneName': _selectedZoneName,
        'referralCode': _referralController.text.trim().toUpperCase(),
        if (_selectedGender != null) 'gender': _selectedGender,
      });
      if (!mounted) return;
      if (res['error'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['error'].toString()), backgroundColor: AppColors.red));
      } else {
        Navigator.pushNamed(
          context,
          FaceCapturePage.route,
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
    return RegStepScaffold(
      step: CapRegSteps.personal,
      stepLabel: 'Personal details',
      title: 'Tell us about yourself',
      subtitle: 'This is how riders and our team will know you.',
      bottom: CapButton(label: 'Continue', loading: _loading, onPressed: _submit),
      children: [
        Form(
          key: _form,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CapField(
              label: 'Full name',
              required: true,
              child: TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: Cap.input(hint: 'As on your driving licence'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Full name is required' : null,
              ),
            ),
            CapField(
              label: 'Mobile number',
              child: TextFormField(
                readOnly: true,
                initialValue: '+91 $_phone',
                decoration: Cap.input(suffix: Icon(Icons.lock_outline_rounded, size: 18, color: Cap.muted)),
                style: Cap.body(size: 15, weight: FontWeight.w600, color: Cap.muted),
              ),
            ),
            CapField(
              label: 'Email address',
              child: TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: Cap.input(hint: 'name@example.com'),
                validator: (v) {
                  if (v != null && v.isNotEmpty && !v.contains('@')) return 'Enter valid email';
                  return null;
                },
              ),
            ),
            // Optional and self-declared — used only so a rider who asks
            // for a female driver can actually be matched with one; never
            // shown publicly and never required to keep driving.
            CapField(
              label: 'Gender (optional)',
              child: DropdownButtonFormField<String>(
                value: _selectedGender,
                isExpanded: true,
                decoration: Cap.input(hint: 'Select'),
                items: const [
                  DropdownMenuItem(value: 'female', child: Text('Female')),
                  DropdownMenuItem(value: 'male', child: Text('Male')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (v) => setState(() => _selectedGender = v),
              ),
            ),
            CapField(
              label: 'State',
              required: true,
              child: DropdownButtonFormField<String>(
                value: _selectedState,
                // Without isExpanded the dropdown sizes to its longest
                // item, so a long state name overflowed a 320pt screen.
                // Expanding it makes the label ellipsise instead.
                isExpanded: true,
                decoration: Cap.input(hint: 'Select your state'),
                items: _indianStates.map((s) => DropdownMenuItem(
                  value: s,
                  child: Text(s, maxLines: 1, overflow: TextOverflow.ellipsis),
                )).toList(),
                onChanged: (v) => setState(() => _selectedState = v),
              ),
            ),
            CapField(
              label: 'City / zone',
              required: true,
              child: _zonesLoading
                  ? Container(
                      height: 54,
                      decoration: BoxDecoration(color: Cap.tile, borderRadius: BorderRadius.circular(12)),
                      alignment: Alignment.center,
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Cap.accent)),
                    )
                  : DropdownButtonFormField<String>(
                      value: _selectedZoneId,
                      isExpanded: true,
                      decoration: Cap.input(hint: 'Where will you drive?'),
                      items: _zones.map((z) => DropdownMenuItem(
                        value: z['_id'] as String? ?? z['id'] as String?,
                        child: Text(z['name'] as String? ?? '',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
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
            ),
            CapField(
              label: 'Referral code (optional)',
              child: TextFormField(
                controller: _referralController,
                textCapitalization: TextCapitalization.characters,
                decoration: Cap.input(hint: "Enter a friend's code"),
              ),
            ),
            // Profile photo + identity signature are captured live on the
            // next screen (camera, not a gallery picker) — that shot becomes
            // both.
            const CapBanner(
              icon: Icons.face_retouching_natural_rounded,
              text: "Next, you'll take a quick selfie. It becomes your profile photo and keeps your account secure.",
            ),
          ]),
        ),
      ],
    );
  }
}
