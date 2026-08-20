import 'package:flutter/material.dart';
import '../theme/brand.dart';

/// Official Thia & Nicole Laundry Shop logo.
///
/// Uses the brand asset directly. Falls back to the icon asset, then to a
/// laundry glyph, so a missing/broken asset never produces a blank space.
class BrandLogo extends StatelessWidget {
  final double size;
  final bool showName;

  const BrandLogo({
    super.key,
    this.size = 96,
    this.showName = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Image.asset(
            BrandAssets.logo,
            width: size,
            height: size * 0.667,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => Image.asset(
              BrandAssets.icon,
              width: size,
              height: size,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => Icon(
                Icons.local_laundry_service,
                size: size,
                color: BrandColors.navy,
              ),
            ),
          ),
        ),
        if (showName) ...[
          const SizedBox(height: 12),
          Text(
            BrandAssets.shopName,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: BrandColors.navy,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          Text(
            BrandAssets.shopTagline,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: BrandColors.aqua,
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}