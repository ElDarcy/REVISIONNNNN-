import 'package:flutter/material.dart';
import '../core/constants/app_sizes.dart';
import '../core/theme/brand.dart';

class AppTheme {
  static const Color primaryColor = BrandColors.navy;
  static const Color secondaryColor = BrandColors.aqua;
  static const Color accentColor = BrandColors.aquaLight;
  static const Color successColor = BrandColors.success;
  static const Color warningColor = BrandColors.warning;
  static const Color errorColor = BrandColors.error;
  static const Color surfaceColor = BrandColors.background;
  static const Color darkSurfaceColor = BrandColors.navyDark;

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: BrandColors.navy,
      brightness: Brightness.light,
      primary: BrandColors.navy,
      onPrimary: Colors.white,
      secondary: BrandColors.aqua,
      onSecondary: BrandColors.navyDark,
      surface: Colors.white,
      onSurface: BrandColors.textPrimary,
      error: BrandColors.error,
    );

    final baseTextTheme = ThemeData.light().textTheme;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: BrandColors.background,
      textTheme: baseTextTheme
          .copyWith(
            displaySmall: baseTextTheme.displaySmall?.copyWith(
              color: BrandColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
            headlineMedium: baseTextTheme.headlineMedium?.copyWith(
              color: BrandColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
            titleLarge: baseTextTheme.titleLarge?.copyWith(
              color: BrandColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
            titleMedium: baseTextTheme.titleMedium?.copyWith(
              color: BrandColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
            bodyLarge: baseTextTheme.bodyLarge?.copyWith(
              color: BrandColors.textPrimary,
            ),
            bodyMedium: baseTextTheme.bodyMedium?.copyWith(
              color: BrandColors.textSecondary,
            ),
            labelLarge: baseTextTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          )
          .apply(bodyColor: BrandColors.textPrimary),
      appBarTheme: const AppBarTheme(
        backgroundColor: BrandColors.navy,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: AppSizes.fontLg,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: BrandColors.navy,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, AppSizes.buttonHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.paddingLg,
            vertical: AppSizes.paddingMd,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
          elevation: 0,
          textStyle: const TextStyle(
            fontSize: AppSizes.fontLg,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: BrandColors.navy,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, AppSizes.buttonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
          textStyle: const TextStyle(
            fontSize: AppSizes.fontLg,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: BrandColors.navy,
          side: const BorderSide(color: BrandColors.navy),
          minimumSize: const Size(64, AppSizes.buttonHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.paddingLg,
            vertical: AppSizes.paddingMd,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
          textStyle: const TextStyle(
            fontSize: AppSizes.fontLg,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: BrandColors.aqua,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSizes.paddingMd,
          vertical: AppSizes.paddingMd,
        ),
        labelStyle: const TextStyle(color: BrandColors.textSecondary),
        hintStyle: const TextStyle(color: BrandColors.textHint),
        prefixIconColor: BrandColors.textSecondary,
        suffixIconColor: BrandColors.textSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          borderSide: const BorderSide(color: BrandColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          borderSide: const BorderSide(color: BrandColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          borderSide: const BorderSide(color: BrandColors.navy, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          borderSide: const BorderSide(color: BrandColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          borderSide: const BorderSide(color: BrandColors.error, width: 1.6),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusLg),
          side: const BorderSide(color: BrandColors.border),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusPill),
        ),
        side: const BorderSide(color: BrandColors.border),
        labelStyle: const TextStyle(color: BrandColors.textPrimary),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusXl),
        ),
        titleTextStyle: const TextStyle(
          color: BrandColors.textPrimary,
          fontSize: AppSizes.fontXl,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: const TextStyle(color: BrandColors.textSecondary),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSizes.radiusXl),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: BrandColors.navy,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: BrandColors.aqua,
        linearTrackColor: BrandColors.aquaSoft,
      ),
      dividerTheme: const DividerThemeData(
        color: BrandColors.border,
        thickness: AppSizes.dividerThickness,
        space: AppSizes.spaceMd,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: BrandColors.navy,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }

  static ThemeData get darkTheme {
    final base = ThemeData.dark().textTheme;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: BrandColors.navy,
        brightness: Brightness.dark,
        primary: BrandColors.aqua,
        secondary: BrandColors.aquaLight,
        surface: BrandColors.navyDark,
        error: BrandColors.error,
      ),
      scaffoldBackgroundColor: BrandColors.navyDark,
      textTheme: base.apply(bodyColor: Colors.white),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0A1B3A),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
    );
  }
}