import 'package:flutter/material.dart';
import '../constants/app_sizes.dart';
import '../theme/brand.dart';

/// Mobile-first, web-responsive shell for auth/onboarding screens.
///
/// Centers content in a max-width column (so it looks right on phones AND
/// desktop/Flutter web), is keyboard-safe, and optionally shows a brand header.
class OnboardingScaffold extends StatelessWidget {
  final Widget child;
  final Widget? header;
  final bool resizeToAvoidBottomInset;
  final Color background;

  const OnboardingScaffold({
    super.key,
    required this.child,
    this.header,
    this.resizeToAvoidBottomInset = true,
    this.background = BrandColors.background,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      backgroundColor: background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSizes.paddingLg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSizes.maxContentWidth,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (header != null) ...[header!, const SizedBox(height: 32)],
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}