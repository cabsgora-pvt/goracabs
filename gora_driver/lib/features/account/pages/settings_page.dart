import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../providers/theme_provider.dart';
import '../../../widgets/captain_ui/captain_ui.dart';
import 'legal_pages.dart';
import '../../ride/widgets/voice_settings_card.dart';

class SettingsPage extends StatelessWidget {
  static const route = '/settings';
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();

    return Scaffold(
      appBar: blueAppBar('Settings'),
      backgroundColor: Cap.tile,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          CapMenuGroup(title: 'Appearance', children: [
            CapMenuRow(
              icon: theme.isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
              label: 'Dark mode',
              sub: 'Switch between light and dark theme',
              trailing: Switch(
                value: theme.isDark,
                onChanged: (v) => context.read<ThemeProvider>().toggle(v),
                activeTrackColor: AppColors.primary,
              ),
            ),
          ]),

          const CapSectionTitle('Navigation', padding: EdgeInsets.fromLTRB(4, 18, 4, 8)),
          const VoiceSettingsCard(),

          CapMenuGroup(title: 'Legal', children: [
            CapMenuRow(icon: Icons.help_outline_rounded, label: 'FAQ', onTap: () => Navigator.pushNamed(context, '/faq')),
            CapMenuRow(icon: Icons.privacy_tip_outlined, label: 'Privacy Policy', onTap: () => Navigator.pushNamed(context, PrivacyPolicyPage.route)),
            CapMenuRow(icon: Icons.description_outlined, label: 'Terms of Service', onTap: () => Navigator.pushNamed(context, TermsPage.route)),
          ]),

          CapMenuGroup(title: 'About', children: [
            CapMenuRow(icon: Icons.info_outline_rounded, label: 'App Version 1.0.0', onTap: () {}),
            CapMenuRow(icon: Icons.star_outline_rounded, label: 'Rate the App', onTap: () {}),
          ]),
        ],
      ),
    );
  }
}
