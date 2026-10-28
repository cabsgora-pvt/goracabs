import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../../widgets/captain_ui/captain_ui.dart';

// Legacy shared widgets, restyled onto the captain_ui visual language so every
// screen that still uses them picks up the new look. New code should use
// captain_ui directly.

// Primary Button — full-width navy CTA.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  final double? width;
  const PrimaryButton({super.key, required this.label, this.onTap, this.loading = false, this.width});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width ?? double.infinity,
      child: CapButton(label: label, onPressed: onTap, loading: loading),
    );
  }
}

// Section Header
class SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const SectionHeader({super.key, required this.title, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: AppColors.textDark)),
        ),
        if (action != null)
          GestureDetector(
            onTap: onAction,
            child: Text(action!, style: TextStyle(fontSize: 13, color: Cap.accent, fontWeight: FontWeight.w700)),
          ),
      ],
    );
  }
}

// Info Tile
class InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const InfoTile({super.key, required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 18, color: AppColors.textDark),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 11.5, color: AppColors.textGrey, fontWeight: FontWeight.w500)),
            Text(value,
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textDark)),
          ]),
        ),
      ],
    );
  }
}

// Stat Card — flat summary card with a big number.
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  const StatCard({super.key, required this.label, required this.value, required this.icon, this.color});

  @override
  Widget build(BuildContext context) => CapStatCard(label: label, value: value, icon: icon, accent: color);
}

// App bar used by every inner screen. Kept under its old name so the many
// call sites stay untouched; it now draws the white Uber-style bar.
PreferredSizeWidget blueAppBar(String title, {List<Widget>? actions, bool showBack = true, BuildContext? context}) {
  return capAppBar(title, actions: actions, showBack: showBack);
}

// Loader overlay
class AppLoader extends StatelessWidget {
  const AppLoader({super.key});
  @override
  Widget build(BuildContext context) {
    return Center(child: CircularProgressIndicator(color: Cap.accent, strokeWidth: 2.6));
  }
}

// Empty state
class EmptyState extends StatelessWidget {
  final String message;
  final IconData icon;
  const EmptyState({super.key, required this.message, required this.icon});

  @override
  Widget build(BuildContext context) => CapEmpty(icon: icon, title: message);
}

// Menu row for account-style lists.
class MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  const MenuRow({super.key, required this.icon, required this.label, required this.onTap, this.iconColor});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: AppColors.cardBg, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 19, color: iconColor ?? AppColors.textDark),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.textDark)),
          ),
          Icon(Icons.chevron_right_rounded, color: AppColors.textGrey, size: 22),
        ]),
      ),
    );
  }
}
