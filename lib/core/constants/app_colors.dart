import 'package:flutter/material.dart';
import '../theme/brand.dart';

/// Application color palette.
///
/// Values are derived from the Thia & Nicole Laundry Shop logo brand tokens.
/// Semantic colors (success/warning/error/status/role) remain separate from
/// the brand palette.
class AppColors {
  // Brand
  static const Color primary = BrandColors.navy;
  static const Color primaryLight = BrandColors.aqua;
  static const Color primaryDark = BrandColors.navyDark;
  static const Color secondary = BrandColors.aqua;
  static const Color accent = BrandColors.aquaLight;

  static const Color success = BrandColors.success;
  static const Color warning = BrandColors.warning;
  static const Color error = BrandColors.error;
  static const Color info = BrandColors.aqua;

  static const Color backgroundLight = BrandColors.background;
  static const Color backgroundDark = BrandColors.navyDark;
  static const Color surfaceLight = BrandColors.surface;
  static const Color surfaceDark = BrandColors.navy;

  static const Color textPrimary = BrandColors.textPrimary;
  static const Color textSecondary = BrandColors.textSecondary;
  static const Color textLight = Colors.white;
  static const Color textHint = BrandColors.textHint;

  static const Color borderLight = BrandColors.border;
  static const Color borderDark = Color(0xFF3A4A63);

  static const Color pendingColor = BrandColors.warning;
  static const Color processingColor = BrandColors.aqua;
  static const Color completedColor = BrandColors.success;
  static const Color cancelledColor = BrandColors.error;

  // Role Colors
  static const Color customerColor = BrandColors.aqua;
  static const Color staffColor = BrandColors.warning;
  static const Color adminColor = BrandColors.error;

  // Brand tints for backgrounds / subtle accents
  static const Color aquaSoft = BrandColors.aquaSoft;
  static const Color navySoft = BrandColors.navySoft;
}