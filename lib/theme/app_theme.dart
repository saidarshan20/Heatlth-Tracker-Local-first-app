import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFF4FC3A1);
  static const primaryContainer = Color(0xFF1A3D35);
  static const secondary = Color(0xFF7ECFB3);
  static const surface = Color(0xFF0F1F1C);
  static const surfaceVariant = Color(0xFF162B26);
  static const surfaceContainer = Color(0xFF1C2F2A);
  static const surfaceContainerHigh = Color(0xFF243830);
  static const onSurface = Color(0xFFE8F5F1);
  static const onSurfaceVariant = Color(0xFF9BBFB5);
  static const outline = Color(0xFF2E4B44);
  static const error = Color(0xFFFF6B6B);
  static const warning = Color(0xFFFFB347);
  static const success = Color(0xFF4FC3A1);
  static const water = Color(0xFF5BC8F5);
}

class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'DMSans',
      scaffoldBackgroundColor: AppColors.surface,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        primaryContainer: AppColors.primaryContainer,
        secondary: AppColors.secondary,
        surface: AppColors.surface,
        error: AppColors.error,
        onSurface: AppColors.onSurface,
        onPrimary: AppColors.surface,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.outline),
        ),
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 0,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.surfaceContainerHigh,
        contentTextStyle: TextStyle(
          fontFamily: 'DMSans',
          color: AppColors.onSurface,
          fontSize: 13,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surfaceContainer,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(fontFamily: 'DMSans', fontSize: 10, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontFamily: 'DMSans', fontSize: 10),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
    );
  }
}
