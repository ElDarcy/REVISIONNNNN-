import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/brand.dart';
import '../../../providers/auth_provider.dart';

/// Brand splash screen shown at `/`.
///
/// Displays the official Thia & Nicole logo with a restrained water-bubble
/// animation, waits for the Firebase auth-state snapshot to resolve
/// ([AuthProvider.isInitialized]) and holds for a minimum duration so there is
/// never a blank white screen or a decision jump, then routes to the correct
/// screen (Login, or the user's role dashboard / customer location setup).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  static const _minDisplay = Duration(milliseconds: 1800);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..forward();
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.92, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _decideAndGo() async {
    if (_started) return;
    _started = true;
    await Future<void>.delayed(SplashScreen._minDisplay);
    if (!mounted) return;

    final auth = context.read<AuthProvider>();
    final user = auth.user;
    final route = user == null ? '/login' : auth.startRouteFor(user);

    Navigator.of(context).pushNamedAndRemoveUntil(route, (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.isInitialized && !_started) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _decideAndGo());
    }

    return Scaffold(
      backgroundColor: BrandColors.navyDark,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              BrandColors.navyMid,
              BrandColors.navy,
              BrandColors.navyDark,
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Subtle rising water bubbles.
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => CustomPaint(
                    painter: _BubblePainter(
                      progress: _controller.value,
                      color: BrandColors.aqua.withValues(alpha: 0.35),
                    ),
                  ),
                ),
              ),
              Column(
                children: [
                  Expanded(
                    child: Center(
                      child: FadeTransition(
                        opacity: _fade,
                        child: ScaleTransition(
                          scale: _scale,
                          child: _BrandMark(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSizes.spaceLg),
                  const Text(
                    BrandAssets.shopName,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: AppSizes.fontXxl,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    BrandAssets.shopTagline,
                    style: TextStyle(
                      color: BrandColors.aquaLight,
                      fontSize: AppSizes.fontLg,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    BrandAssets.welcomeMessage,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: AppSizes.fontSm,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSizes.spaceXl),
                  const SizedBox(
                    width: 140,
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      backgroundColor: Colors.white24,
                      color: BrandColors.aquaLight,
                      borderRadius: BorderRadius.all(
                        Radius.circular(AppSizes.radiusPill),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSizes.spaceMd),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// White "logo card" with the official logo artwork, sized for mobile.
class _BrandMark extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.spaceLg),
      margin: const EdgeInsets.symmetric(horizontal: AppSizes.spaceXxl),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSizes.radiusXl),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Image.asset(
        BrandAssets.logo,
        width: 260,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => Image.asset(
          BrandAssets.icon,
          width: 120,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const Icon(
            Icons.local_laundry_service,
            size: 96,
            color: BrandColors.navy,
          ),
        ),
      ),
    );
  }
}

/// Restrained rising-bubble painter (subtle water motif).
class _BubblePainter extends CustomPainter {
  final double progress;
  final Color color;

  _BubblePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rand = math.Random(7);
    final paint = Paint()..color = color;
    for (var i = 0; i < 26; i++) {
      final seed = (rand.nextDouble() * 1000).floor();
      final x = rand.nextDouble() * size.width;
      final yBase = rand.nextDouble() * size.height;
      final radius = 2 + rand.nextDouble() * 5;
      final speed = 0.2 + rand.nextDouble() * 0.5;
      final rise = (progress * speed * size.height * 0.55) % size.height;
      final y = (yBase - rise + size.height) % size.height;
      final alpha = (1 - progress.abs() * 0.6).clamp(0.1, 0.5) * (0.4 + seed % 6 / 10);
      paint.color = color.withValues(alpha: alpha);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BubblePainter oldDelegate) =>
      oldDelegate.progress != progress;
}