import 'package:flutter/material.dart';
import '../constants/app_sizes.dart';
import '../theme/brand.dart';

/// Animated success check (scale + fade-in) used on completion transitions,
/// e.g. after a location is saved.
class SuccessCheck extends StatelessWidget {
  final bool animate;
  final double size;

  const SuccessCheck({
    super.key,
    this.animate = true,
    this.size = 96,
  });

  @override
  Widget build(BuildContext context) {
    Widget check = Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: BrandColors.success,
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.check, color: Colors.white, size: size * 0.55),
    );

    if (animate) {
      check = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 450),
        curve: Curves.elasticOut,
        builder: (context, value, child) => Transform.scale(
          scale: value,
          child: Opacity(opacity: value.clamp(0, 1), child: child),
        ),
        child: check,
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.spaceMd),
        child: check,
      ),
    );
  }
}