import 'package:flutter/material.dart';
import '../constants/app_sizes.dart';
import '../theme/brand.dart';

/// A "or continue with …" divider used between email and social sign-in.
class SocialDivider extends StatelessWidget {
  final String label;

  const SocialDivider({
    super.key,
    this.label = 'or continue with',
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.spaceMd),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: BrandColors.textHint,
              letterSpacing: 0.4,
            ),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}