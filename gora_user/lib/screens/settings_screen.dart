import 'package:flutter/material.dart';
import '../config/app_version.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/theme_provider.dart';
import '../utils/emergency_contacts_store.dart';
import '../utils/phone_input_formatter.dart';
import 'delete_account_screen.dart';

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
            'Version $kAppVersion',
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
            'Ask us to close your account',
            () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DeleteAccountScreen())),
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
}

class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key});

  @override
  State<EmergencyContactsScreen> createState() => _EmergencyContactsScreenState();
}

/// The rider's emergency contacts, kept on the server (and cached on the
/// phone for SOS when offline) — see EmergencyContactsStore.
class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  List<Map<String, String>> _contacts = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // The cached list at once, then the server's.
    EmergencyContactsStore.load().then((c) {
      if (mounted && _loading) setState(() => _contacts = c);
    });
    _sync();
  }

  Future<void> _sync() async {
    final c = await EmergencyContactsStore.sync();
    if (mounted) setState(() { _contacts = c; _loading = false; });
  }

  void _say(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _remove(Map<String, String> contact) async {
    if (_busy) return;
    setState(() => _busy = true);
    final err = await EmergencyContactsStore.remove(contact);
    final list = await EmergencyContactsStore.load();
    if (!mounted) return;
    setState(() { _busy = false; _contacts = list; });
    if (err != null) _say(err);
  }

  @override
  Widget build(BuildContext context) {
    final full = _contacts.length >= EmergencyContactsStore.maxContacts;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Contacts'),
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Add contact',
            onPressed: full || _busy ? null : _showAddContactDialog,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _loading && _contacts.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _contacts.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.contacts_outlined, size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text('No emergency contacts added', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _showAddContactDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Contact'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _contacts.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                if (i == _contacts.length) {
                  return Text(
                    full
                        ? 'You can keep up to ${EmergencyContactsStore.maxContacts} contacts.'
                        : 'Saved to your Gora account, so they move with you to a new phone.',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textGrey),
                  );
                }
                final contact = _contacts[i];
                final synced = (contact['id'] ?? '').isNotEmpty;
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).dividerColor),
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
                            Text(contact['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            const SizedBox(height: 4),
                            Text(contact['phone'] ?? '', style: const TextStyle(fontSize: 13, color: AppTheme.textGrey)),
                            if ((contact['relation'] ?? '').isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(contact['relation']!, style: const TextStyle(fontSize: 12, color: AppTheme.textGrey)),
                            ],
                            if (!synced)
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Text('Saved on this phone — syncs when online',
                                    style: TextStyle(fontSize: 11.5, color: AppTheme.textGrey)),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove',
                        onPressed: _busy ? null : () => _remove(contact),
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
    String? error;
    bool saving = false;

    showDialog(
      context: context,
      builder: (dctx) => StatefulBuilder(builder: (dctx, setD) => AlertDialog(
        title: const Text('Add Emergency Contact'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('sos-contact-phone'),
                controller: phoneController,
                keyboardType: TextInputType.phone,
                inputFormatters: const [IndianPhoneInputFormatter()],
                decoration: InputDecoration(
                  labelText: 'Mobile number',
                  prefixText: '+91 ',
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
              if (error != null) ...[
                const SizedBox(height: 10),
                Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12.5)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel')),
          ElevatedButton(
            key: const ValueKey('sos-contact-add'),
            onPressed: saving ? null : () async {
              setD(() { saving = true; error = null; });
              final err = await EmergencyContactsStore.add(
                nameController.text, phoneController.text,
                relation: relationController.text.trim().isEmpty ? 'Other' : relationController.text.trim(),
              );
              if (err != null) {
                if (dctx.mounted) setD(() { saving = false; error = err; });
                return;
              }
              if (dctx.mounted) Navigator.pop(dctx);
              final list = await EmergencyContactsStore.load();
              if (mounted) setState(() => _contacts = list);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryBlue),
            child: const Text('Add', style: TextStyle(color: Colors.white)),
          ),
        ],
      )),
    );
  }
}
