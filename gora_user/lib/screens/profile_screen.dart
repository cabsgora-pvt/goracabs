import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/user_provider.dart';
import '../services/api_service.dart';
import '../config/app_config.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Controllers only used when _isEditing = true
  TextEditingController? _name;
  TextEditingController? _email;
  TextEditingController? _city;
  TextEditingController? _idNumber;

  bool _isEditing = false;
  bool _saving = false;
  Uint8List? _newPicBytes;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    // Always load fresh from API
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UserProvider>().loadProfile();
    });
  }

  @override
  void dispose() {
    _name?.dispose();
    _email?.dispose();
    _city?.dispose();
    _idNumber?.dispose();
    super.dispose();
  }

  void _startEditing(UserProvider u) {
    _name     = TextEditingController(text: u.name);
    _email    = TextEditingController(text: u.email);
    _city     = TextEditingController(text: u.city);
    _idNumber = TextEditingController(text: u.idNumber);
    setState(() => _isEditing = true);
  }

  void _cancelEditing(UserProvider u) {
    _name?.dispose(); _email?.dispose();
    _city?.dispose(); _idNumber?.dispose();
    setState(() { _isEditing = false; _newPicBytes = null; });
  }

  Future<void> _pickPhoto() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() => _newPicBytes = bytes);
    final url = await ApiService.uploadProfilePic(picked);
    if (url != null && mounted) {
      final relUrl = url.replaceFirst(AppConfig.serverBaseUrl, '');
      context.read<UserProvider>().setUser({
        ...?context.read<UserProvider>().user,
        'profilePicUrl': relUrl,
      });
    }
  }

  Future<void> _save(UserProvider u) async {
    setState(() => _saving = true);
    final ok = await u.updateProfile(
      name:      _name?.text.trim()     ?? u.name,
      city:      _city?.text.trim()     ?? u.city,
      email:     _email?.text.trim()    ?? u.email,
      idNumber:  _idNumber?.text.trim() ?? u.idNumber,
    );
    if (!mounted) return;
    _name?.dispose(); _email?.dispose();
    _city?.dispose(); _idNumber?.dispose();
    setState(() { _saving = false; _isEditing = false; _newPicBytes = null; });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Profile updated!' : 'Failed to update'),
      backgroundColor: ok ? Colors.green : Colors.red,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final u = context.watch<UserProvider>(); // rebuilds on every API load
    final picUrl = u.profilePicUrl;
    final displayName = u.name.isNotEmpty ? u.name : (u.phone.isNotEmpty ? '+91 ${u.phone}' : '');

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        elevation: 0,
        actions: [
          if (u.loading)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryBlue)),
            )
          else if (_saving)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else ...[
            if (_isEditing) ...[
              IconButton(
                icon: const Icon(Icons.check, color: Colors.green),
                onPressed: () => _save(u),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.red),
                onPressed: () => _cancelEditing(u),
              ),
            ] else
              IconButton(
                icon: const Icon(Icons.edit, color: AppTheme.primaryBlue),
                onPressed: () => _startEditing(u),
              ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ── Profile photo card ──
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withAlpha(13), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: Column(children: [
                GestureDetector(
                  onTap: _isEditing ? _pickPhoto : null,
                  child: Stack(children: [
                    Container(
                      width: 110, height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.primaryBlue.withAlpha(60), width: 3),
                      ),
                      child: ClipOval(
                        child: _newPicBytes != null
                            ? Image.memory(_newPicBytes!, fit: BoxFit.cover)
                            : picUrl.isNotEmpty
                                ? Image.network(
                                    AppConfig.imageUrl(picUrl),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => _avatarFallback(displayName),
                                  )
                                : _avatarFallback(displayName),
                      ),
                    ),
                    if (_isEditing)
                      Positioned(
                        bottom: 2, right: 2,
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: const BoxDecoration(color: AppTheme.primaryBlue, shape: BoxShape.circle),
                          child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 14),
                Text(
                  u.name.isNotEmpty ? u.name : (u.loading ? 'Loading...' : 'Tap edit to add name'),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                ),
                if (u.phone.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('+91 ${u.phone}',
                        style: TextStyle(color: Colors.grey[500], fontSize: 14)),
                  ),
              ]),
            ),

            // ── Fields ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Personal Information',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  _fieldRow(Icons.person_outline, 'Full Name',
                      _isEditing ? _name! : TextEditingController(text: u.name)),
                  const SizedBox(height: 14),
                  _fieldRow(Icons.phone_outlined, 'Phone Number',
                      TextEditingController(text: u.phone), readOnly: true),
                  const SizedBox(height: 14),
                  _fieldRow(Icons.email_outlined, 'Email',
                      _isEditing ? _email! : TextEditingController(text: u.email),
                      keyboard: TextInputType.emailAddress),
                  const SizedBox(height: 14),
                  _fieldRow(Icons.location_city_outlined, 'City',
                      _isEditing ? _city! : TextEditingController(text: u.city)),
                  const SizedBox(height: 14),
                  _fieldRow(Icons.badge_outlined, 'ID Number',
                      _isEditing ? _idNumber! : TextEditingController(text: u.idNumber)),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatarFallback(String name) {
    return Container(
      color: AppTheme.primaryBlue.withAlpha(25),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
        ),
      ),
    );
  }

  Widget _fieldRow(IconData icon, String label, TextEditingController ctrl,
      {TextInputType? keyboard, bool readOnly = false}) {
    final editable = _isEditing && !readOnly;
    return TextField(
      controller: ctrl,
      enabled: editable,
      readOnly: !editable,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppTheme.primaryBlue),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: editable ? Theme.of(context).cardColor : Colors.grey[100],
      ),
    );
  }
}
