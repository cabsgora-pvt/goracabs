import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../providers/theme_provider.dart';
import 'legal_pages.dart';

class SettingsPage extends StatelessWidget {
  static const route = '/settings';
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final cardColor = Theme.of(context).cardColor;

    Widget section(String t) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textGrey, letterSpacing: 0.5)),
        );

    return Scaffold(
      appBar: blueAppBar('Settings'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          section('Appearance'),
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                  child: Icon(theme.isDark ? Icons.dark_mode : Icons.light_mode, size: 20, color: AppColors.primary)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Dark Mode', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: onSurface)),
                Text('Switch between light and dark theme', style: TextStyle(fontSize: 11, color: AppColors.textGrey)),
              ])),
              Switch(value: theme.isDark, onChanged: (v) => context.read<ThemeProvider>().toggle(v), activeColor: AppColors.primary),
            ]),
          ),

          section('Legal'),
          MenuRow(icon: Icons.help_outline, label: 'FAQ', onTap: () => Navigator.pushNamed(context, '/faq')),
          MenuRow(icon: Icons.privacy_tip_outlined, label: 'Privacy Policy', onTap: () => Navigator.pushNamed(context, PrivacyPolicyPage.route)),
          MenuRow(icon: Icons.description_outlined, label: 'Terms of Service', onTap: () => Navigator.pushNamed(context, TermsPage.route)),

          section('About'),
          MenuRow(icon: Icons.info_outline, label: 'App Version 1.0.0', onTap: () {}),
          MenuRow(icon: Icons.star_outline, label: 'Rate the App', onTap: () {}),
        ]),
      ),
    );
  }
}
