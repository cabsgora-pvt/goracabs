import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/user_provider.dart';
import '../services/api_service.dart';
import '../config/app_config.dart';
import '../widgets/ride_ui/ride_ui.dart';
import '../widgets/premium.dart';

/// Rider profile: photo, name and contact details, in the same tile style as
/// the booking screens. Viewing is read-only; "Edit profile" turns the rows
/// into fields with one Save button at the bottom.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Controllers exist only while editing.
  TextEditingController? _name;
  TextEditingController? _email;
  TextEditingController? _city;
  TextEditingController? _idNumber;

  bool _isEditing = false;
  bool _saving = false;
  bool _uploadingPhoto = false;
  Uint8List? _newPicBytes;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    // Always load fresh from the API.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UserProvider>().loadProfile();
    });
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _disposeControllers() {
    _name?.dispose();
    _email?.dispose();
    _city?.dispose();
    _idNumber?.dispose();
    _name = _email = _city = _idNumber = null;
  }

  void _startEditing(UserProvider u) {
    _name = TextEditingController(text: u.name);
    _email = TextEditingController(text: u.email);
    _city = TextEditingController(text: u.city);
    _idNumber = TextEditingController(text: u.idNumber);
    setState(() => _isEditing = true);
  }

  void _cancelEditing() {
    FocusScope.of(context).unfocus();
    _disposeControllers();
    setState(() => _isEditing = false);
  }

  Future<void> _pickPhoto() async {
    if (_uploadingPhoto) return;
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _newPicBytes = bytes;
      _uploadingPhoto = true;
    });
    final url = await ApiService.uploadProfilePic(picked);
    if (!mounted) return;
    setState(() => _uploadingPhoto = false);
    if (url != null) {
      final relUrl = url.replaceFirst(AppConfig.serverBaseUrl, '');
      context.read<UserProvider>().setUser({
        ...?context.read<UserProvider>().user,
        'profilePicUrl': relUrl,
      });
      _snack('Photo updated', ok: true);
    } else {
      setState(() => _newPicBytes = null);
      _snack('Could not upload the photo. Please try again.', ok: false);
    }
  }

  Future<void> _save(UserProvider u) async {
    final email = _email?.text.trim() ?? u.email;
    if (email.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _snack('Please enter a valid email address', ok: false);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    final ok = await u.updateProfile(
      name: _name?.text.trim() ?? u.name,
      city: _city?.text.trim() ?? u.city,
      email: email,
      idNumber: _idNumber?.text.trim() ?? u.idNumber,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      _disposeControllers();
      setState(() => _isEditing = false);
    }
    _snack(ok ? 'Profile updated' : 'Failed to update. Please try again.', ok: ok);
  }

  void _snack(String msg, {required bool ok}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: ok ? Colors.green.shade700 : Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final u = context.watch<UserProvider>(); // rebuilds on every API load
    final displayName = u.name.isNotEmpty ? u.name : (u.phone.isNotEmpty ? '+91 ${u.phone}' : '');

    return PopScope(
      // Back while editing leaves edit mode instead of the screen.
      canPop: !_isEditing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isEditing) _cancelEditing();
      },
      child: Scaffold(
        backgroundColor: Premium.page(context),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Premium.page(context),
          surfaceTintColor: Colors.transparent,
          title: Text(_isEditing ? 'Edit profile' : 'Profile', style: Premium.title(context, size: 20)),
          centerTitle: false,
          actions: [
            if (u.loading && !_isEditing)
              const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_isEditing)
              TextButton(
                onPressed: _saving ? null : _cancelEditing,
                child: Text('Cancel', style: RideUi.body(context, size: 14, weight: FontWeight.w700)),
              ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () => context.read<UserProvider>().loadProfile(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(RideUi.gutter, 4, RideUi.gutter, 24),
            children: [
              _header(u, displayName),
              const SizedBox(height: 26),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Text('ACCOUNT', style: Premium.overline(context)),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text('Personal information', style: Premium.title(context, size: 18)),
              ),
              const SizedBox(height: 12),
              if (_isEditing) ..._editFields() else _detailsCard(u),
            ],
          ),
        ),
        // Lifted above the keyboard, or Save sits hidden behind it while typing.
        bottomNavigationBar: _isEditing
            ? Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
                child: PrimaryCtaBar(
                  label: _saving ? 'Saving…' : 'Save changes',
                  icon: Icons.check_rounded,
                  onPressed: _saving ? null : () => _save(u),
                ),
              )
            : null,
      ),
    );
  }

  // ── Header: photo, name, phone, Edit ─────────────────────────────────────
  Widget _header(UserProvider u, String displayName) {
    final picUrl = u.profilePicUrl;
    return PremiumHeaderCard(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      child: Column(children: [
        Row(children: [
          GestureDetector(
            onTap: _pickPhoto,
            child: Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 76, height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
                child: ClipOval(
                  child: _newPicBytes != null
                      ? Image.memory(_newPicBytes!, fit: BoxFit.cover)
                      : picUrl.isNotEmpty
                          ? Image.network(
                              AppConfig.imageUrl(picUrl),
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => _avatarFallback(displayName),
                            )
                          : _avatarFallback(displayName),
                ),
              ),
              if (_uploadingPhoto)
                const Positioned.fill(
                  child: Center(
                    child: SizedBox(width: 24, height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
                  ),
                ),
              Positioned(
                bottom: -2, right: -2,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: RideUi.cta,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 14),
                ),
              ),
            ]),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                u.name.isNotEmpty ? u.name : (u.loading ? 'Loading…' : 'Add your name'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: -0.4, height: 1.15),
              ),
              if (u.phone.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(children: [
                  Flexible(
                    child: Text('+91 ${u.phone}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.verified_rounded, size: 16, color: Colors.greenAccent.shade200),
                ]),
              ],
              if (u.city.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(children: [
                  Icon(Icons.location_on_outlined, size: 14, color: Colors.white.withValues(alpha: 0.75)),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(u.city,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13)),
                  ),
                ]),
              ],
            ]),
          ),
        ]),
        if (!_isEditing) ...[
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: u.loading && u.user == null ? null : () => _startEditing(u),
              icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.white),
              label: const Text('Edit profile',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                backgroundColor: Colors.white.withValues(alpha: 0.12),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _avatarFallback(String name) {
    return Container(
      color: Colors.white,
      child: Center(
        child: Text(
          name.isNotEmpty ? name.trim()[0].toUpperCase() : '?',
          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: AppTheme.primaryBlue),
        ),
      ),
    );
  }

  // ── View mode: one tile with a row per detail ───────────────────────────
  Widget _detailsCard(UserProvider u) {
    final rows = <Widget>[
      _detailRow(Icons.person_outline_rounded, 'Full name', u.name),
      _detailRow(Icons.phone_outlined, 'Phone number', u.phone.isNotEmpty ? '+91 ${u.phone}' : '',
          trailing: _verifiedBadge()),
      _detailRow(Icons.email_outlined, 'Email', u.email),
      _detailRow(Icons.location_city_outlined, 'City', u.city),
      _detailRow(Icons.badge_outlined, 'ID number', u.idNumber),
    ];
    return PremiumCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(height: 1, indent: 54, color: Premium.hairline(context)),
          rows[i],
        ],
      ]),
    );
  }

  Widget _detailRow(IconData icon, String label, String value, {Widget? trailing}) {
    final empty = value.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        PremiumIcon(icon, size: 40),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: Premium.label(context, size: 12)),
            const SizedBox(height: 2),
            Text(
              empty ? 'Not added' : value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: empty
                  ? Premium.label(context, size: 14.5)
                  : Premium.body(context, size: 15, weight: FontWeight.w700),
            ),
          ]),
        ),
        ?trailing,
      ]),
    );
  }

  Widget _verifiedBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text('Verified',
            style: TextStyle(color: Colors.green.shade700, fontSize: 11, fontWeight: FontWeight.w800)),
      );

  // ── Edit mode: grey field boxes ─────────────────────────────────────────
  List<Widget> _editFields() {
    final u = context.read<UserProvider>();
    return [
      _editField(Icons.person_outline_rounded, 'Full name', 'Add your name', _name!,
          capitalization: TextCapitalization.words),
      _lockedField(Icons.phone_outlined, 'Phone number', u.phone.isNotEmpty ? '+91 ${u.phone}' : ''),
      _editField(Icons.email_outlined, 'Email', 'Add email', _email!, keyboard: TextInputType.emailAddress),
      _editField(Icons.location_city_outlined, 'City', 'Add city', _city!, capitalization: TextCapitalization.words),
      _editField(Icons.badge_outlined, 'ID number', 'Add ID number', _idNumber!,
          capitalization: TextCapitalization.characters),
    ];
  }

  Widget _editField(IconData icon, String label, String hint, TextEditingController ctrl,
      {TextInputType? keyboard, TextCapitalization capitalization = TextCapitalization.none}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: RideUi.caption(context, size: 12.5)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: RideUi.fieldBox(context),
          child: Row(children: [
            Icon(icon, size: 19, color: RideUi.accent(context)),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: ctrl,
                keyboardType: keyboard,
                textCapitalization: capitalization,
                enabled: !_saving,
                decoration: RideUi.bareInput(context, hint, vertical: 14, fontSize: 15),
                style: RideUi.body(context, size: 15, weight: FontWeight.w600),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _lockedField(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: RideUi.caption(context, size: 12.5)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: RideUi.fieldBox(context),
          child: Row(children: [
            Icon(icon, size: 19, color: RideUi.muted(context)),
            const SizedBox(width: 10),
            Expanded(child: Text(value, style: RideUi.body(context, size: 15, weight: FontWeight.w600))),
            Icon(Icons.lock_outline_rounded, size: 16, color: RideUi.muted(context)),
          ]),
        ),
        const SizedBox(height: 4),
        Text('Phone number is your login and cannot be changed here.', style: RideUi.caption(context, size: 11.5)),
      ]),
    );
  }
}
