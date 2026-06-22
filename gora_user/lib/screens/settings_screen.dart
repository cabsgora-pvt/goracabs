import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/theme_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _pushNotifications = true;
  bool _emailNotifications = false;
  bool _smsNotifications = true;
  bool _locationServices = true;
  bool _shareData = false;
  String _language = 'English';

  @override
  Widget build(BuildContext context) {
    final themeProv = context.watch<ThemeProvider>();
    final themeLabel = themeProv.mode == ThemeMode.dark
        ? 'Dark'
        : (themeProv.mode == ThemeMode.system ? 'System Default' : 'Light');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        elevation: 0,
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Account Settings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textGrey)),
          const SizedBox(height: 12),
          _buildSettingTile(
            Icons.person_outline,
            'Edit Profile',
            'Update your personal information',
            () {},
          ),
          _buildSettingTile(
            Icons.lock_outline,
            'Change Password',
            'Update your password',
            () => _showChangePasswordDialog(),
          ),
          _buildSettingTile(
            Icons.phone_outlined,
            'Change Phone Number',
            'Update your mobile number',
            () {},
          ),
          _buildSettingTile(
            Icons.email_outlined,
            'Change Email',
            'Update your email address',
            () {},
          ),
          const SizedBox(height: 24),
          const Text('Notifications', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textGrey)),
          const SizedBox(height: 12),
          _buildSwitchTile(
            Icons.notifications_outlined,
            'Push Notifications',
            'Receive ride updates and offers',
            _pushNotifications,
            (val) => setState(() => _pushNotifications = val),
          ),
          _buildSwitchTile(
            Icons.email_outlined,
            'Email Notifications',
            'Receive updates via email',
            _emailNotifications,
            (val) => setState(() => _emailNotifications = val),
          ),
          _buildSwitchTile(
            Icons.sms_outlined,
            'SMS Notifications',
            'Receive SMS alerts',
            _smsNotifications,
            (val) => setState(() => _smsNotifications = val),
          ),
          const SizedBox(height: 24),
          const Text('Privacy & Security', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textGrey)),
          const SizedBox(height: 12),
          _buildSwitchTile(
            Icons.location_on_outlined,
            'Location Services',
            'Allow app to access your location',
            _locationServices,
            (val) => setState(() => _locationServices = val),
          ),
          _buildSwitchTile(
            Icons.analytics_outlined,
            'Share Usage Data',
            'Help improve app experience',
            _shareData,
            (val) => setState(() => _shareData = val),
          ),
          _buildSettingTile(
            Icons.shield_outlined,
            'Privacy Policy',
            'Read our privacy policy',
            () {},
          ),
          _buildSettingTile(
            Icons.description_outlined,
            'Terms & Conditions',
            'Read terms of service',
            () {},
          ),
          const SizedBox(height: 24),
          const Text('App Preferences', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textGrey)),
          const SizedBox(height: 12),
          // Quick dark mode switch
          _buildSwitchTile(
            themeProv.isDark ? Icons.dark_mode : Icons.light_mode,
            'Dark Mode',
            themeProv.isDark ? 'Dark theme is on' : 'Light theme is on',
            themeProv.isDark,
            (val) => context.read<ThemeProvider>().toggleDark(val),
          ),
          _buildDropdownTile(
            Icons.language_outlined,
            'Language',
            _language,
            ['English', 'Hindi', 'Tamil', 'Telugu', 'Bengali'],
            (val) => setState(() => _language = val!),
          ),
          _buildDropdownTile(
            Icons.brightness_6_outlined,
            'Theme',
            themeLabel,
            ['Light', 'Dark', 'System Default'],
            (val) {
              final m = val == 'Dark' ? ThemeMode.dark : (val == 'System Default' ? ThemeMode.system : ThemeMode.light);
              context.read<ThemeProvider>().setMode(m);
            },
          ),
          _buildSettingTile(
            Icons.payment_outlined,
            'Payment Methods',
            'Manage saved payment methods',
            () {},
          ),
          _buildSettingTile(
            Icons.contacts_outlined,
            'Emergency Contacts',
            'Manage SOS contacts',
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EmergencyContactsScreen())),
          ),
          const SizedBox(height: 24),
          const Text('About', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textGrey)),
          const SizedBox(height: 12),
          _buildSettingTile(
            Icons.info_outline,
            'About Gora Cabs',
            'Version 1.0.0',
            () {},
          ),
          _buildSettingTile(
            Icons.rate_review_outlined,
            'Rate Us',
            'Rate us on Play Store',
            () {},
          ),
          _buildSettingTile(
            Icons.share_outlined,
            'Share App',
            'Invite friends to Gora Cabs',
            () {},
          ),
          const SizedBox(height: 24),
          _buildSettingTile(
            Icons.delete_outline,
            'Delete Account',
            'Permanently delete your account',
            () => _showDeleteAccountDialog(),
            color: Colors.red,
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSettingTile(IconData icon, String title, String subtitle, VoidCallback onTap, {Color? color}) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (color ?? AppTheme.primaryBlue).withAlpha(20),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color ?? AppTheme.primaryBlue, size: 22),
      ),
      title: Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.textGrey)),
      trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
      onTap: onTap,
    );
  }

  Widget _buildSwitchTile(IconData icon, String title, String subtitle, bool value, Function(bool) onChanged) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.primaryBlue.withAlpha(20),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: AppTheme.primaryBlue, size: 22),
      ),
      title: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.textGrey)),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: AppTheme.primaryBlue,
      ),
    );
  }

  Widget _buildDropdownTile(IconData icon, String title, String value, List<String> items, Function(String?) onChanged) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.primaryBlue.withAlpha(20),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: AppTheme.primaryBlue, size: 22),
      ),
      title: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      trailing: DropdownButton<String>(
        value: value,
        underline: const SizedBox(),
        items: items.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
        onChanged: onChanged,
      ),
    );
  }

  void _showChangePasswordDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Change Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Current Password',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'New Password',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Confirm New Password',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Password changed successfully')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
            child: const Text('Change', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text('Are you sure you want to permanently delete your account? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key});

  @override
  State<EmergencyContactsScreen> createState() => _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  final List<Map<String, String>> _contacts = [
    {'name': 'John Doe', 'phone': '+91 98765 43210', 'relation': 'Father'},
    {'name': 'Jane Doe', 'phone': '+91 98765 43211', 'relation': 'Mother'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Contacts'),
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: () => _showAddContactDialog(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _contacts.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.contacts_outlined, size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text('No emergency contacts added', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () => _showAddContactDialog(),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Contact'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _contacts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final contact = _contacts[i];
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: AppTheme.primaryBlue.withAlpha(30),
                        child: const Icon(Icons.person, color: AppTheme.primaryBlue, size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(contact['name']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            const SizedBox(height: 4),
                            Text(contact['phone']!, style: const TextStyle(fontSize: 13, color: AppTheme.textGrey)),
                            const SizedBox(height: 2),
                            Text(contact['relation']!, style: const TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() => _contacts.removeAt(i)),
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  void _showAddContactDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final relationController = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Emergency Contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Phone Number',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: relationController,
              decoration: InputDecoration(
                labelText: 'Relation',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty && phoneController.text.isNotEmpty) {
                setState(() {
                  _contacts.add({
                    'name': nameController.text,
                    'phone': phoneController.text,
                    'relation': relationController.text.isEmpty ? 'Other' : relationController.text,
                  });
                });
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
            child: const Text('Add', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
