import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';

class SettingsPage extends StatefulWidget {
  static const route = '/settings';
  const SettingsPage({super.key});
  @override State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _notifications = true, _sounds = true, _vibration = false, _darkMode = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: blueAppBar('Settings'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _section('Preferences'),
          _switchTile('Push Notifications', 'Receive ride & payment alerts', Icons.notifications, _notifications, (v) => setState(() => _notifications = v)),
          _switchTile('Sound Alerts', 'Play sound for new requests', Icons.volume_up, _sounds, (v) => setState(() => _sounds = v)),
          _switchTile('Vibration', 'Vibrate for alerts', Icons.vibration, _vibration, (v) => setState(() => _vibration = v)),
          _switchTile('Dark Mode', 'Switch to dark theme', Icons.dark_mode, _darkMode, (v) => setState(() => _darkMode = v)),
          _section('App'),
          MenuRow(icon: Icons.language, label: 'Language', onTap: () {}),
          MenuRow(icon: Icons.map, label: 'Map Settings', onTap: () {}),
          MenuRow(icon: Icons.help_outline, label: 'FAQ', onTap: () => Navigator.pushNamed(context, '/faq')),
          MenuRow(icon: Icons.privacy_tip_outlined, label: 'Privacy Policy', onTap: () {}),
          MenuRow(icon: Icons.description_outlined, label: 'Terms of Service', onTap: () {}),
          _section('About'),
          MenuRow(icon: Icons.info_outline, label: 'App Version 1.0.0', onTap: () {}),
          MenuRow(icon: Icons.star_outline, label: 'Rate the App', onTap: () {}),
        ]),
      ),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textGrey, letterSpacing: 0.5)),
  );

  Widget _switchTile(String title, String sub, IconData icon, bool val, ValueChanged<bool> onChanged) => Row(children: [
    Container(padding: const EdgeInsets.all(8), margin: const EdgeInsets.only(bottom: 4), decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, size: 20, color: AppColors.primary)),
    const SizedBox(width: 14),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textDark)),
      Text(sub, style: const TextStyle(fontSize: 11, color: AppColors.textGrey)),
    ])),
    Switch(value: val, onChanged: onChanged, activeColor: AppColors.primary),
  ]);
}
