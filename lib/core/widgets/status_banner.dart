import 'package:flutter/material.dart';
import '../constants/app_sizes.dart';
import '../theme/brand.dart';

enum BannerTone { info, success, warning, error }

/// Soft, tinted banner for status/feedback messages (used by onboarding
/// and auth flows). Follows the brand's soft-tint language.
class StatusBanner extends StatelessWidget {
  final BannerTone tone;
  final String message;
  final IconData? icon;

  const StatusBanner({
    super.key,
    required this.tone,
    required this.message,
    this.icon,
  });

  Color get _color {
    switch (tone) {
      case BannerTone.info:
        return BrandColors.aqua;
      case BannerTone.success:
        return BrandColors.success;
      case BannerTone.warning:
        return BrandColors.warning;
      case BannerTone.error:
        return BrandColors.error;
    }
  }

  Color get _background => _color.withValues(alpha: 0.1);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.spaceMd),
      decoration: BoxDecoration(
        color: _background,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(color: _color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon ?? (tone == BannerTone.error ? Icons.error_outline : Icons.info_outline),
            color: _color,
            size: AppSizes.iconMd,
          ),
          const SizedBox(width: AppSizes.spaceSm + 4),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}