import 'package:flutter/material.dart';

/// ألوان هوية WIZANO المعتمدة (وثيقة 01 — قسم 11).
class WizanoColors {
  WizanoColors._();

  static const Color navy = Color(0xFF041B3A);
  static const Color navyBright = Color(0xFF073B78);
  static const Color teal = Color(0xFF14D7B0);
  static const Color blue = Color(0xFF0878F9);
  static const Color gold = Color(0xFFFFC94A);
  static const Color background = Color(0xFFF2F7FF);
  static const Color surface = Colors.white;
  static const Color textDark = Color(0xFF1F2933);
  static const Color textMuted = Color(0xFF6B7280);
  static const Color error = Color(0xFFDC2626);
}

class WizanoTheme {
  WizanoTheme._();

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: WizanoColors.navy,
        primary: WizanoColors.navy,
        secondary: WizanoColors.teal,
        tertiary: WizanoColors.gold,
        error: WizanoColors.error,
        surface: WizanoColors.surface,
      ),
      scaffoldBackgroundColor: WizanoColors.background,
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: WizanoColors.navy,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: WizanoColors.navy,
          foregroundColor: Colors.white,
          minimumSize: const Size(200, 48),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: WizanoColors.surface,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: WizanoColors.teal.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
            color: states.contains(WidgetState.selected)
                ? WizanoColors.navy
                : WizanoColors.textMuted,
          ),
        ),
      ),
    );
  }
}
