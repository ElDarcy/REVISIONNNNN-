import 'package:flutter/material.dart';

/// Official Thia & Nicole Laundry Shop brand assets.
///
/// The logo files are the source of truth for the visual identity. Treat them
/// as official assets — never recreate, redraw, recolor, or replace them.
class BrandAssets {
  static const String logo = 'assets/images/logo/thia_nicole_logo.png.jpg';
  static const String icon = 'assets/images/logo/thia_nicole_icon.png.png';
  static const String splash = 'assets/images/splash/thia_nicole_splash.jpg';

  static const String shopName = 'Thia & Nicole';
  static const String shopTagline = 'Laundry Shop';
  static const String welcomeMessage =
      'Fresh, clean laundry — delivered with care.';
}

/// Brand palette derived directly from the logo artwork (pixel sampling).
///
/// - Deep navy is the primary "ink" of the logo and the main brand color.
/// - Aqua/teal is the subtle water accent.
/// - White / soft neutral tints carry the clean, premium feel.
class BrandColors {
  static const Color navy = Color(0xFF0F254C);
  static const Color navyDark = Color(0xFF0A1B3A);
  static const Color navyMid = Color(0xFF0B2B51);

  static const Color aqua = Color(0xFF42B0BD);
  static const Color aquaLight = Color(0xFF53C3CF);
  static const Color aquaSoft = Color(0xFFE3F4F6);

  static const Color navySoft = Color(0xFFEEF1F7);

  static const Color background = Color(0xFFF7F9FC);
  static const Color surface = Colors.white;

  static const Color textPrimary = Color(0xFF10244A);
  static const Color textSecondary = Color(0xFF5A6B80);
  static const Color textHint = Color(0xFF9AA7B8);
  static const Color border = Color(0xFFE6EAF1);

  static const Color success = Color(0xFF2E9E5B);
  static const Color warning = Color(0xFFE8A23D);
  static const Color error = Color(0xFFD94848);

  static const Color textOnNavy = Colors.white;
}