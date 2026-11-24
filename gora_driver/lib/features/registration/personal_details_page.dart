import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/driver_provider.dart';
import '../../core/constants/app_colors.dart';
import '../../widgets/captain_ui/captain_ui.dart';
import 'widgets/reg_motion.dart';
import 'widgets/reg_step_scaffold.dart';
import 'widgets/reg_ui.dart';
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
        // 409 REGISTRATION_LOCKED: already submitted — the server's text says
        // what can no longer be changed here (zone / gender / name).
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res['error'].toString()),
          backgroundColor: AppColors.red,
          duration: Duration(seconds: res['code'] == 'REGISTRATION_LOCKED' ? 7 : 4),
        ));
      } else {
        if (res['referralRewardOnApproval'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Referral code applied. Referral bonus is paid after approval.'),
            backgroundColor: AppColors.green,
          ));
        }
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
      bottom: RegCta(label: 'Continue', loading: _loading, onPressed: _submit),
      staggerChildren: false,
      children: [
        // Sections only group the fields visually: every field, validator and
        // value sent to /register/personal is unchanged.
        Form(
          key: _form,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            RegEntrance(index: RegStepScaffold.firstChildIndex, child: RegSectionCard(
              icon: Icons.person_rounded,
              color: RegPalette.blue,
              title: 'About you',
              caption: 'Your name exactly as on your licence.',
              children: [
                RegField(
                  label: 'Full name',
                  required: true,
                  child: TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: regInput(hint: 'As on your driving licence', icon: Icons.person_outline_rounded),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Full name is required' : null,
                  ),
                ),
                RegField(
                  label: 'Mobile number',
                  child: TextFormField(
                    readOnly: true,
                    initialValue: '+91 $_phone',
                    decoration: regInput(icon: Icons.phone_iphone_rounded, iconColor: RegPalette.green,
                        suffix: Icon(Icons.lock_outline_rounded, size: 18, color: Cap.muted)),
                    style: Cap.body(size: 15, weight: FontWeight.w600, color: Cap.muted),
                  ),
                ),
                RegField(
                  label: 'Email address',
                  child: TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: regInput(hint: 'name@example.com', icon: Icons.alternate_email_rounded, iconColor: RegPalette.purple),
                    validator: (v) {
                      if (v != null && v.isNotEmpty && !v.contains('@')) return 'Enter valid email';
                      return null;
                    },
                  ),
                ),
                // Optional and self-declared — used only so a rider who asks
                // for a female driver can actually be matched with one; never
                // shown publicly and never required to keep driving.
                RegField(
                  label: 'Gender (optional)',
                  child: DropdownButtonFormField<String>(
                    value: _selectedGender,
                    isExpanded: true,
                    decoration: regInput(hint: 'Select', icon: Icons.wc_rounded, iconColor: RegPalette.pink),
                    items: const [
                      DropdownMenuItem(value: 'female', child: Text('Female')),
                      DropdownMenuItem(value: 'male', child: Text('Male')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: (v) => setState(() => _selectedGender = v),
                  ),
                ),
              ],
            )),
            RegEntrance(index: RegStepScaffold.firstChildIndex + 1, child: RegSectionCard(
              icon: Icons.place_rounded,
              color: RegPalette.orange,
              title: 'Where you will drive',
              caption: 'You will get trips in this city.',
              children: [
                RegField(
                  label: 'State',
                  required: true,
                  child: DropdownButtonFormField<String>(
                    value: _selectedState,
                    // Without isExpanded the dropdown sizes to its longest
                    // item, so a long state name overflowed a 320pt screen.
                    // Expanding it makes the label ellipsise instead.
                    isExpanded: true,
                    decoration: regInput(hint: 'Select your state', icon: Icons.map_outlined, iconColor: RegPalette.orange),
                    items: _indianStates.map((s) => DropdownMenuItem(
                      value: s,
                      child: Text(s, maxLines: 1, overflow: TextOverflow.ellipsis),
                    )).toList(),
                    onChanged: (v) => setState(() => _selectedState = v),
                  ),
                ),
                RegField(
                  label: 'City / zone',
                  required: true,
                  child: _zonesLoading
                      ? Container(
                          height: 56,
                          decoration: BoxDecoration(
                            color: RegPalette.field,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: RegPalette.hairline, width: 1.2),
                          ),
                          alignment: Alignment.center,
                          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Cap.accent)),
                        )
                      : DropdownButtonFormField<String>(
                          value: _selectedZoneId,
                          isExpanded: true,
                          decoration: regInput(hint: 'Where will you drive?', icon: Icons.location_city_rounded, iconColor: RegPalette.teal),
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
              ],
            )),
            RegEntrance(index: RegStepScaffold.firstChildIndex + 2, child: RegSectionCard(
              icon: Icons.card_giftcard_rounded,
              color: RegPalette.green,
              title: 'Referral',
              children: [
                RegField(
                  label: 'Referral code (optional)',
                  child: TextFormField(
                    controller: _referralController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: regInput(hint: "Enter a friend's code", icon: Icons.redeem_rounded, iconColor: RegPalette.green),
                  ),
                ),
              ],
            )),
            // Profile photo + identity signature are captured live on the
            // next screen (camera, not a gallery picker) — that shot becomes
            // both.
            const RegEntrance(index: RegStepScaffold.firstChildIndex + 3, child: _NextUpCard(
              text: "Next, you'll take a quick selfie. It becomes your profile photo and keeps your account secure.",
            )),
          ]),
        ),
      ],
    );
  }
}

/// "Up next" teaser for the selfie step.
class _NextUpCard extends StatelessWidget {
  final String text;
  const _NextUpCard({required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [RegPalette.orange.withValues(alpha: 0.12), RegPalette.orange.withValues(alpha: 0.04)],
          ),
          border: Border.all(color: RegPalette.orange.withValues(alpha: 0.22)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const RegIconBadge(icon: Icons.face_retouching_natural_rounded, color: RegPalette.orange, size: 40),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: Cap.caption(size: 13, color: Cap.ink).copyWith(height: 1.4))),
        ]),
      );
}
