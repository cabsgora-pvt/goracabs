import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Brand colours, taken from the Gora logo: royal blue and orange on a
  // deep navy ground. Blue leads (buttons, selection, links); orange is the
  // accent (offers, badges, highlights) — the logo's own balance.
  static const Color primaryBlue = Color(0xFF0A3CC8);
  static const Color lightBlue = Color(0xFF3B6BF0);
  static const Color deepBlue = Color(0xFF020820);
  static const Color brandOrange = Color(0xFFFF7603);
  /// The logo orange a touch deeper, for filled buttons with white text.
  static const Color ctaOrange = Color(0xFFF26A00);
  static const Color orangeSoft = Color(0xFFFFF1E6);
  static const Color blueSoft = Color(0xFFEAF0FF);
  // Kept for existing references; now the logo orange rather than teal.
  static const Color accentTeal = brandOrange;
  static const Color softPurple = Color(0xFF9C27B0);
  
  // Background colors
  static const Color backgroundLight = Color(0xFFFAFAFA);
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color cardBackground = Color(0xFFFFFFFF);
  
  // Text colors
  static const Color textDark = Color(0xFF212121);
  static const Color textMedium = Color(0xFF757575);
  static const Color textLight = Color(0xFFBDBDBD);
  
  // Backward compatibility
  static const Color textGrey = textMedium;
  
  // Gradient definitions
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryBlue, lightBlue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient accentGradient = LinearGradient(
    colors: [brandOrange, Color(0xFFFF9A45)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF4CAF50), Color(0xFF81C784)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Headings (display / headline / title styles) in Poppins, body text in
  /// the platform font. Off by default — tests and previews must not fetch
  /// fonts over the network — and switched on in main(). google_fonts caches
  /// the font after the first download; until then (or offline) headings
  /// simply render in the platform font.
  static bool useDisplayFont = false;

  /// [base] in the display font when it is on.
  static TextStyle display(TextStyle base) {
    if (!useDisplayFont) return base;
    try {
      return GoogleFonts.poppins(textStyle: base);
    } catch (_) {
      return base;
    }
  }

  static ThemeData _finish(ThemeData t) {
    if (!useDisplayFont) return t;
    final tt = t.textTheme;
    TextStyle? d(TextStyle? s) => s == null ? null : display(s);
    return t.copyWith(
      textTheme: tt.copyWith(
        displayLarge: d(tt.displayLarge), displayMedium: d(tt.displayMedium), displaySmall: d(tt.displaySmall),
        headlineLarge: d(tt.headlineLarge), headlineMedium: d(tt.headlineMedium), headlineSmall: d(tt.headlineSmall),
        titleLarge: d(tt.titleLarge),
      ),
      appBarTheme: t.appBarTheme.copyWith(titleTextStyle: d(t.appBarTheme.titleTextStyle)),
    );
  }

  static ThemeData get lightTheme {
    return _finish(ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        primary: primaryBlue,
        onPrimary: Colors.white,
        surface: surfaceWhite,
        onSurface: textDark,
        background: backgroundLight,
        onBackground: textDark,
        secondary: accentTeal,
        onSecondary: Colors.white,
      ),
      scaffoldBackgroundColor: backgroundLight,
      appBarTheme: AppBarTheme(
        backgroundColor: surfaceWhite,
        foregroundColor: textDark,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: const TextStyle(
          color: textDark,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: const IconThemeData(color: textDark),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: ctaOrange,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 4,
          shadowColor: ctaOrange.withOpacity(0.3),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: cardBackground,
        elevation: 8,
        shadowColor: Colors.black.withOpacity(0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceWhite,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: textLight.withOpacity(0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: textLight.withOpacity(0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primaryBlue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFD32F2F), width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        hintStyle: TextStyle(color: textLight, fontSize: 15),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: textDark,
          fontWeight: FontWeight.bold,
          fontSize: 32,
          letterSpacing: -0.5,
        ),
        headlineMedium: TextStyle(
          color: textDark,
          fontWeight: FontWeight.bold,
          fontSize: 24,
          letterSpacing: -0.25,
        ),
        headlineSmall: TextStyle(
          color: textDark,
          fontWeight: FontWeight.w600,
          fontSize: 20,
        ),
        titleLarge: TextStyle(
          color: textDark,
          fontWeight: FontWeight.w600,
          fontSize: 18,
        ),
        titleMedium: TextStyle(
          color: textDark,
          fontWeight: FontWeight.w500,
          fontSize: 16,
        ),
        bodyLarge: TextStyle(
          color: textDark,
          fontSize: 16,
          height: 1.5,
        ),
        bodyMedium: TextStyle(
          color: textMedium,
          fontSize: 14,
          height: 1.4,
        ),
        bodySmall: TextStyle(
          color: textLight,
          fontSize: 12,
          height: 1.3,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surfaceWhite,
        selectedItemColor: primaryBlue,
        unselectedItemColor: textLight,
        elevation: 20,
        type: BottomNavigationBarType.fixed,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    ));
  }

  // ── Dark theme ──────────────────────────────────────────────────
  static const Color darkBg      = Color(0xFF020820); // app background — the logo's navy
  static const Color darkSurface = Color(0xFF111A3A); // cards / sheets
  static const Color darkPrimary = Color(0xFF5B86F5); // logo blue lightened for contrast on dark

  static ThemeData get darkTheme {
    return _finish(ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: darkPrimary,
        onPrimary: Colors.white,
        surface: darkSurface,
        onSurface: Colors.white,
        background: darkBg,
        onBackground: Colors.white,
        secondary: accentTeal,
        onSecondary: Colors.black,
      ),
      scaffoldBackgroundColor: darkBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: darkSurface,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: darkPrimary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      cardTheme: CardThemeData(
        color: darkSurface,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.white.withOpacity(0.15))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.white.withOpacity(0.15))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: darkPrimary, width: 2)),
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 15),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: darkSurface,
        selectedItemColor: darkPrimary,
        unselectedItemColor: Colors.white54,
        type: BottomNavigationBarType.fixed,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: darkPrimary,
        foregroundColor: Colors.white,
      ),
      dialogTheme: const DialogThemeData(backgroundColor: darkSurface),
      bottomSheetTheme: const BottomSheetThemeData(backgroundColor: darkSurface),
    ));
  }

  // Helper methods for gradients
  static BoxDecoration primaryGradientDecoration({
    double borderRadius = 16,
    List<BoxShadow>? boxShadow,
  }) {
    return BoxDecoration(
      gradient: primaryGradient,
      borderRadius: BorderRadius.circular(borderRadius),
      boxShadow: boxShadow ?? [
        BoxShadow(
          color: primaryBlue.withOpacity(0.3),
          blurRadius: 12,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }
  
  static BoxDecoration accentGradientDecoration({
    double borderRadius = 16,
    List<BoxShadow>? boxShadow,
  }) {
    return BoxDecoration(
      gradient: accentGradient,
      borderRadius: BorderRadius.circular(borderRadius),
      boxShadow: boxShadow ?? [
        BoxShadow(
          color: accentTeal.withOpacity(0.3),
          blurRadius: 12,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }
  
  static BoxDecoration cardDecoration({
    double borderRadius = 20,
    Color? color,
  }) {
    return BoxDecoration(
      color: color ?? cardBackground,
      borderRadius: BorderRadius.circular(borderRadius),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.08),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }
}
