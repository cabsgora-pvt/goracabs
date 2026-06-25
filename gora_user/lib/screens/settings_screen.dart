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
  @override
  Widget build(BuildContext context) {
    final themeProv = context.watch<ThemeProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        elevation: 0,
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
          _buildSettingTile(
            Icons.contacts_outlined,
            'Emergency Contacts',
            'Manage SOS contacts',
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EmergencyContactsScreen())),
          ),
          const SizedBox(height: 24),
          const Text('Legal', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textGrey)),
          const SizedBox(height: 12),
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
