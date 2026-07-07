import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

// ── Shared date helpers + a premium date-input field ──
// Use these everywhere a date is shown or entered so the whole app is
// consistent: dd-MM-yyyy format and one branded picker.

/// Format a date as dd-MM-yyyy (e.g. 05-07-2026).
String fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

/// Parse a stored date string. Accepts dd-MM-yyyy (our format) and
/// yyyy-MM-dd / ISO (legacy) so old data still opens correctly.
DateTime? parseDate(String? s) {
  if (s == null || s.trim().isEmpty) return null;
  final t = s.trim();
  // dd-MM-yyyy
  final m = RegExp(r'^(\d{2})-(\d{2})-(\d{4})$').firstMatch(t);
  if (m != null) {
    return DateTime(int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!));
  }
  return DateTime.tryParse(t); // yyyy-MM-dd or full ISO
}

/// Show a brand-themed date picker.
Future<DateTime?> pickDate(BuildContext context, {DateTime? initial, DateTime? first, DateTime? last}) {
  final now = DateTime.now();
  return showDatePicker(
    context: context,
    initialDate: initial ?? now,
    firstDate: first ?? DateTime(now.year - 10),
    lastDate: last ?? DateTime(now.year + 20),
    builder: (context, child) => Theme(
      data: Theme.of(context).copyWith(
        colorScheme: const ColorScheme.light(
          primary: AppColors.primary,
          onPrimary: Colors.white,
          onSurface: Color(0xFF0D1B2A),
        ),
        textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: AppColors.primary)),
        dialogBackgroundColor: Colors.white,
      ),
      child: child!,
    ),
  );
}

/// A premium, tappable date field: label + calendar chip + value in dd-MM-yyyy.
class DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final String hint;
  final VoidCallback onTap;
  const DateField({super.key, required this.label, required this.value, required this.onTap, this.hint = 'Select date'});

  @override
  Widget build(BuildContext context) {
    final has = value != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark, fontSize: 13)),
      const SizedBox(height: 6),
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: has ? AppColors.primary.withOpacity(0.5) : AppColors.divider),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(9)),
              child: const Icon(Icons.calendar_month_rounded, size: 18, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Text(has ? fmtDate(value!) : hint,
                style: TextStyle(color: has ? AppColors.textDark : AppColors.textGrey, fontWeight: FontWeight.w700, fontSize: 14)),
            const Spacer(),
            Icon(Icons.expand_more_rounded, color: AppColors.textGrey, size: 20),
          ]),
        ),
      ),
    ]);
  }
}
