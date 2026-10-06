import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../theme/defensys_tokens.dart';
import '../../theme/login_palette.dart';
import '../branding/defensys_logo_mark.dart';
import 'defensys_skeleton.dart';

/// Smooth, hardware-accelerated shimmer effect wrapper.
/// Sweeps a light-gradient highlight across child widgets continuously.
class DefensysShimmer extends StatefulWidget {
  const DefensysShimmer({
    super.key,
    required this.child,
    this.baseColor,
    this.highlightColor,
    this.duration = const Duration(milliseconds: 1400),
  });

  final Widget child;
  final Color? baseColor;
  final Color? highlightColor;
  final Duration duration;

  @override
  State<DefensysShimmer> createState() => _DefensysShimmerState();
}

class _DefensysShimmerState extends State<DefensysShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = LoginPalette.of(context);
    return RepaintBoundary(child: AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: const Alignment(-1.0, -0.3),
              end: const Alignment(1.0, 0.3),
              colors: [
                widget.baseColor ?? palette.border,
                widget.highlightColor ?? palette.inputFill,
                widget.baseColor ?? palette.border,
              ],
              stops: const [0.1, 0.5, 0.9],
              transform: _SlidingGradientTransform(
                slidePercent: _controller.value,
              ),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    ));
  }
}

class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform({required this.slidePercent});

  final double slidePercent;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    if (bounds.width <= 0) return Matrix4.identity();
    return Matrix4.translationValues(
      bounds.width * (slidePercent * 2.0 - 1.0),
      0.0,
      0.0,
    );
  }
}

/// Dynamic vector wave painter for mobile login screen and its skeleton,
/// matching the institutional USTP deep maroon & flowing ribbon wave identity.
class HeaderWavePainter extends CustomPainter {
  const HeaderWavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. Dark wine red / garnet base gradient
    final bgRect = Rect.fromLTWH(0, 0, w, h);
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF4D0817),
          Color(0xFF38040F),
          Color(0xFF26020A),
        ],
        stops: [0.0, 0.55, 1.0],
      ).createShader(bgRect);
    canvas.drawRect(bgRect, bgPaint);

    // 2. Upper sweeping deep garnet wave (sweeps across beneath the campus photo)
    final topGarnetPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF6E0D22).withValues(alpha: 0.90),
          const Color(0xFF4A0816).withValues(alpha: 0.95),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h * 0.45))
      ..style = PaintingStyle.fill;

    final topPath = Path();
    topPath.moveTo(0, h * 0.16);
    topPath.cubicTo(
      w * 0.30,
      h * 0.10,
      w * 0.68,
      h * 0.28,
      w,
      h * 0.18,
    );
    topPath.lineTo(w, 0);
    topPath.lineTo(0, 0);
    topPath.close();
    canvas.drawPath(topPath, topGarnetPaint);

    // 3. Graceful translucent silver/white sweeping ribbon wave (Layer A - top flow)
    final whiteRibbonPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.32),
          Colors.white.withValues(alpha: 0.16),
          Colors.white.withValues(alpha: 0.04),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h * 0.50))
      ..style = PaintingStyle.fill;

    final whiteRibbonPath = Path();
    whiteRibbonPath.moveTo(0, h * 0.22);
    whiteRibbonPath.cubicTo(
      w * 0.28,
      h * 0.16,
      w * 0.65,
      h * 0.32,
      w,
      h * 0.22,
    );
    whiteRibbonPath.lineTo(w, h * 0.26);
    whiteRibbonPath.cubicTo(
      w * 0.65,
      h * 0.36,
      w * 0.28,
      h * 0.20,
      0,
      h * 0.26,
    );
    whiteRibbonPath.close();
    canvas.drawPath(whiteRibbonPath, whiteRibbonPaint);

    // 4. Middle sweeping crimson wave layer
    final midGarnetPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF5E0B1B),
          const Color(0xFF38040F),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h * 0.58))
      ..style = PaintingStyle.fill;

    final midGarnetPath = Path();
    midGarnetPath.moveTo(0, h * 0.25);
    midGarnetPath.cubicTo(
      w * 0.32,
      h * 0.19,
      w * 0.68,
      h * 0.35,
      w,
      h * 0.25,
    );
    midGarnetPath.lineTo(w, h * 0.42);
    midGarnetPath.cubicTo(
      w * 0.65,
      h * 0.50,
      w * 0.25,
      h * 0.36,
      0,
      h * 0.40,
    );
    midGarnetPath.close();
    canvas.drawPath(midGarnetPath, midGarnetPaint);

    // 5. Right-side cascading translucent ribbon wave (curves down right margin behind card)
    final rightRibbonPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [
          Colors.white.withValues(alpha: 0.26),
          Colors.white.withValues(alpha: 0.10),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(w * 0.5, h * 0.20, w * 0.5, h * 0.60))
      ..style = PaintingStyle.fill;

    final rightRibbonPath = Path();
    rightRibbonPath.moveTo(w, h * 0.23);
    rightRibbonPath.cubicTo(
      w * 0.76,
      h * 0.36,
      w * 0.82,
      h * 0.58,
      w,
      h * 0.66,
    );
    rightRibbonPath.lineTo(w, h * 0.70);
    rightRibbonPath.cubicTo(
      w * 0.78,
      h * 0.60,
      w * 0.72,
      h * 0.38,
      w,
      h * 0.27,
    );
    rightRibbonPath.close();
    canvas.drawPath(rightRibbonPath, rightRibbonPaint);

    // 6. Left-side subtle crimson wave contour
    final leftWavePaint = Paint()
      ..color = const Color(0xFF5A0A1B).withValues(alpha: 0.60)
      ..style = PaintingStyle.fill;

    final leftPath = Path();
    leftPath.moveTo(0, h * 0.40);
    leftPath.cubicTo(
      w * 0.25,
      h * 0.46,
      w * 0.18,
      h * 0.66,
      0,
      h * 0.72,
    );
    leftPath.close();
    canvas.drawPath(leftPath, leftWavePaint);

    // 7. Bottom sweeping dark wine red wave
    final bottomWavePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF38040F),
          Color(0xFF220208),
        ],
      ).createShader(Rect.fromLTWH(0, h * 0.70, w, h * 0.30))
      ..style = PaintingStyle.fill;

    final bottomPath = Path();
    bottomPath.moveTo(0, h * 0.78);
    bottomPath.cubicTo(
      w * 0.35,
      h * 0.70,
      w * 0.75,
      h * 0.88,
      w,
      h * 0.78,
    );
    bottomPath.lineTo(w, h);
    bottomPath.lineTo(0, h);
    bottomPath.close();
    canvas.drawPath(bottomPath, bottomWavePaint);

    // 8. Bottom accent layer for organic depth
    final bottomAccentPaint = Paint()
      ..color = const Color(0xFF5E0B1B).withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;

    final bottomAccentPath = Path();
    bottomAccentPath.moveTo(0, h * 0.86);
    bottomAccentPath.cubicTo(
      w * 0.40,
      h * 0.80,
      w * 0.80,
      h * 0.94,
      w,
      h * 0.88,
    );
    bottomAccentPath.lineTo(w, h);
    bottomAccentPath.lineTo(0, h);
    bottomAccentPath.close();
    canvas.drawPath(bottomAccentPath, bottomAccentPaint);

    // 9. Bottom-left translucent highlight ribbon
    final bottomRibbonPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [
          Colors.white.withValues(alpha: 0.16),
          Colors.white.withValues(alpha: 0.04),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, h * 0.75, w * 0.75, h * 0.25))
      ..style = PaintingStyle.fill;

    final bottomRibbonPath = Path();
    bottomRibbonPath.moveTo(0, h * 0.81);
    bottomRibbonPath.cubicTo(
      w * 0.30,
      h * 0.73,
      w * 0.60,
      h * 0.85,
      w * 0.82,
      h * 0.81,
    );
    bottomRibbonPath.lineTo(w * 0.82, h * 0.84);
    bottomRibbonPath.cubicTo(
      w * 0.60,
      h * 0.88,
      w * 0.30,
      h * 0.76,
      0,
      h * 0.84,
    );
    bottomRibbonPath.close();
    canvas.drawPath(bottomRibbonPath, bottomRibbonPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Full-screen skeleton placeholder displayed during initial app boot/restore.
/// Replaces the default circular loading spinner with an authentic,
/// responsive layout preview matching the DefenSYS login portal.
class LoginSkeletonScreen extends StatelessWidget {
  const LoginSkeletonScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useWebLayout = kIsWeb && constraints.maxWidth >= 760;
        if (useWebLayout) {
          return _WebLoginSkeleton(constraints: constraints);
        }
        return const _MobileLoginSkeleton();
      },
    );
  }
}

class _MobileLoginSkeleton extends StatelessWidget {
  const _MobileLoginSkeleton();

  @override
  Widget build(BuildContext context) {
    final palette = LoginPalette.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF4D0817),
      body: Stack(
        children: [
          // Background organic curves matching real mobile screen
          const Positioned.fill(
            child: CustomPaint(
              painter: HeaderWavePainter(),
            ),
          ),
          // Watermark logo in upper right of dark background
          Positioned(
            top: -15,
            right: -35,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.14,
                child: DefensysLogoMark(
                  size: 230,
                  customColor: Colors.black,
                ),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 24),
                          // Header Brand Lockup Skeleton
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const DefensysLogoMark(
                                size: 52,
                                colorMode: DefensysLogoColorMode.white,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: DefensysShimmer(
                                  baseColor: Colors.white.withValues(alpha: 0.22),
                                  highlightColor: Colors.white.withValues(alpha: 0.55),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 130,
                                        height: 22,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Container(
                                        width: 180,
                                        height: 13,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Container(
                                        width: 110,
                                        height: 11,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 28),
                          // Theme-aware form surface (floating sheet)
                          Container(
                            decoration: BoxDecoration(
                              color: palette.surface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: palette.border,
                                width: 1.0,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.16),
                                  blurRadius: 24,
                                  offset: const Offset(0, 10),
                                ),
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Stack(
                                children: [
                                  // Faded maroon logo watermark in lower right
                                  Positioned(
                                    bottom: -25,
                                    right: -25,
                                    child: IgnorePointer(
                                      child: Opacity(
                                        opacity: 0.07,
                                        child: Transform.rotate(
                                          angle: -0.12,
                                          child: DefensysLogoMark(
                                            size: 180,
                                            customColor: palette.action,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      // Top Accent Bar (Maroon & Gold Gradient)
                                      Container(
                                        height: 4,
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              DefensysTokens.maroon,
                                              DefensysTokens.gold,
                                            ],
                                            begin: Alignment.centerLeft,
                                            end: Alignment.centerRight,
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
                                        child: DefensysShimmer(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              // Welcome back placeholder
                                              DefensysSkeleton.box(
                                                width: 95,
                                                height: 13,
                                                borderRadius: 4,
                                              ),
                                              const SizedBox(height: 8),
                                              // Sign in headline placeholder
                                              DefensysSkeleton.box(
                                                width: 110,
                                                height: 26,
                                                borderRadius: 6,
                                              ),
                                              const SizedBox(height: 22),
                                              // Field 1 label placeholder
                                              DefensysSkeleton.box(
                                                width: 140,
                                                height: 12,
                                                borderRadius: 4,
                                              ),
                                              const SizedBox(height: 7),
                                              // Field 1 input box placeholder
                                              _buildSkeletonInputBox(
                                                palette: palette,
                                                icon: Icons.person_outline,
                                                hintWidth: 150,
                                              ),
                                              const SizedBox(height: 18),
                                              // Field 2 label placeholder
                                              DefensysSkeleton.box(
                                                width: 75,
                                                height: 12,
                                                borderRadius: 4,
                                              ),
                                              const SizedBox(height: 7),
                                              // Field 2 input box placeholder
                                              _buildSkeletonInputBox(
                                                palette: palette,
                                                icon: Icons.lock_outline,
                                                hintWidth: 90,
                                                hasSuffix: true,
                                              ),
                                              const SizedBox(height: 18),
                                              // Remember me & Forgot password row
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Row(
                                                    children: [
                                                      DefensysSkeleton.box(
                                                        width: 18,
                                                        height: 18,
                                                        borderRadius: 4,
                                                      ),
                                                      const SizedBox(width: 8),
                                                      DefensysSkeleton.box(
                                                        width: 90,
                                                        height: 12,
                                                        borderRadius: 4,
                                                      ),
                                                    ],
                                                  ),
                                                  DefensysSkeleton.box(
                                                    width: 105,
                                                    height: 12,
                                                    borderRadius: 4,
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 24),
                                              // Primary Sign In button placeholder
                                              Container(
                                                height: 52,
                                                width: double.infinity,
                                                decoration: BoxDecoration(
                                                  color: palette.action
                                                      .withValues(alpha: 0.85),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: palette.action
                                                          .withValues(alpha: 0.25),
                                                      blurRadius: 10,
                                                      offset: const Offset(0, 4),
                                                    ),
                                                  ],
                                                ),
                                                alignment: Alignment.center,
                                                child: Container(
                                                  width: 70,
                                                  height: 14,
                                                  decoration: BoxDecoration(
                                                    color: Colors.white
                                                        .withValues(alpha: 0.4),
                                                    borderRadius:
                                                        BorderRadius.circular(4),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 18),
                                              // Divider OR placeholder
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Divider(
                                                      color: palette.border,
                                                      height: 1,
                                                    ),
                                                  ),
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                            horizontal: 12),
                                                    child: DefensysSkeleton.box(
                                                      width: 20,
                                                      height: 10,
                                                      borderRadius: 2,
                                                    ),
                                                  ),
                                                  Expanded(
                                                    child: Divider(
                                                      color: palette.border,
                                                      height: 1,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 18),
                                              // Secondary Guest Panelist button placeholder
                                              Container(
                                                height: 48,
                                                width: double.infinity,
                                                decoration: BoxDecoration(
                                                  color: palette.surface,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  border: Border.all(
                                                      color: palette.inputBorder),
                                                ),
                                                alignment: Alignment.center,
                                                child: DefensysSkeleton.box(
                                                  width: 160,
                                                  height: 13,
                                                  borderRadius: 4,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Spacer(),
                          const SizedBox(height: 20),
                          // Institutional footer placeholder
                          Center(
                            child: DefensysShimmer(
                              baseColor: Colors.white.withValues(alpha: 0.2),
                              highlightColor: Colors.white.withValues(alpha: 0.5),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  DefensysSkeleton.box(
                                    width: 50,
                                    height: 10,
                                    borderRadius: 3,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 12),
                                  DefensysSkeleton.box(
                                    width: 4,
                                    height: 4,
                                    borderRadius: 2,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 12),
                                  DefensysSkeleton.box(
                                    width: 80,
                                    height: 10,
                                    borderRadius: 3,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 12),
                                  DefensysSkeleton.box(
                                    width: 4,
                                    height: 4,
                                    borderRadius: 2,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 12),
                                  DefensysSkeleton.box(
                                    width: 50,
                                    height: 10,
                                    borderRadius: 3,
                                    color: Colors.white,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildSkeletonInputBox({
    required LoginPalette palette,
    required IconData icon,
    required double hintWidth,
    bool hasSuffix = false,
  }) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: palette.inputFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.inputBorder, width: 1.0),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Icon(icon, size: 20, color: palette.muted),
          const SizedBox(width: 12),
          DefensysSkeleton.box(
            width: hintWidth,
            height: 12,
            borderRadius: 4,
          ),
          if (hasSuffix) ...[
            const Spacer(),
            Icon(
              Icons.visibility_outlined,
              size: 20,
              color: palette.muted,
            ),
          ],
        ],
      ),
    );
  }
}

class _WebLoginSkeleton extends StatelessWidget {
  const _WebLoginSkeleton({required this.constraints});

  final BoxConstraints constraints;

  @override
  Widget build(BuildContext context) {
    final palette = LoginPalette.of(context);
    final isCompact = constraints.maxWidth < 980;

    return Scaffold(
      backgroundColor: palette.background,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left Side: Hero Event Carousel Skeleton (60%)
          Expanded(
            flex: isCompact ? 5 : 6,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF2C040D),
                          Color(0xFF4D0817),
                          Color(0xFF1E0309),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.15),
                          Colors.black.withValues(alpha: 0.65),
                        ],
                      ),
                    ),
                  ),
                ),
                // Top Brand Lockup
                Positioned(
                  top: 48,
                  left: 48,
                  right: 48,
                  child: Row(
                    children: [
                      DefensysLogoMark(
                        size: isCompact ? 42 : 52,
                        colorMode: DefensysLogoColorMode.white,
                      ),
                      const SizedBox(width: 14),
                      DefensysShimmer(
                        baseColor: Colors.white.withValues(alpha: 0.25),
                        highlightColor: Colors.white.withValues(alpha: 0.6),
                        child: Container(
                          width: 140,
                          height: isCompact ? 28 : 34,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Bottom Slogan Panel Skeleton
                Positioned(
                  bottom: 64,
                  left: 48,
                  right: 48,
                  child: DefensysShimmer(
                    baseColor: Colors.white.withValues(alpha: 0.2),
                    highlightColor: Colors.white.withValues(alpha: 0.5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: isCompact ? 260 : 380,
                          height: isCompact ? 28 : 38,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: isCompact ? 220 : 320,
                          height: isCompact ? 28 : 38,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: 90,
                          height: 4,
                          decoration: BoxDecoration(
                            color: DefensysTokens.gold,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          width: isCompact ? 300 : 440,
                          height: 13,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: isCompact ? 240 : 350,
                          height: 13,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Right Side: Centered Form Card (40%)
          Expanded(
            flex: isCompact ? 5 : 4,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    palette.background,
                    palette.panel,
                  ],
                ),
              ),
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: isCompact ? 16 : 32,
                    vertical: 24,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Institutional Co-Branded Header Placeholder
                        DefensysShimmer(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: palette.border,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Container(
                                width: 1,
                                height: 32,
                                color: palette.inputBorder,
                              ),
                              const SizedBox(width: 14),
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: palette.border,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Container(
                                width: 1,
                                height: 32,
                                color: palette.inputBorder,
                              ),
                              const SizedBox(width: 14),
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: palette.border,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Web Card Skeleton
                        Container(
                          decoration: BoxDecoration(
                            color: palette.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: palette.border,
                              width: 1.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF0F172A)
                                    .withValues(alpha: 0.06),
                                blurRadius: 28,
                                offset: const Offset(0, 10),
                              ),
                              BoxShadow(
                                color: const Color(0xFF0F172A)
                                    .withValues(alpha: 0.02),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          padding: EdgeInsets.fromLTRB(
                            isCompact ? 24 : 36,
                            34,
                            isCompact ? 24 : 36,
                            30,
                          ),
                          child: DefensysShimmer(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    DefensysSkeleton.box(
                                      width: 44,
                                      height: 44,
                                      borderRadius: 10,
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          DefensysSkeleton.box(
                                            width: 130,
                                            height: 20,
                                            borderRadius: 5,
                                          ),
                                          const SizedBox(height: 6),
                                          DefensysSkeleton.box(
                                            width: 180,
                                            height: 12,
                                            borderRadius: 4,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                DefensysSkeleton.box(
                                  width: 120,
                                  height: 12,
                                  borderRadius: 4,
                                ),
                                const SizedBox(height: 8),
                                _MobileLoginSkeleton._buildSkeletonInputBox(
                                  palette: palette,
                                  icon: Icons.person_outline,
                                  hintWidth: 150,
                                ),
                                const SizedBox(height: 18),
                                DefensysSkeleton.box(
                                  width: 80,
                                  height: 12,
                                  borderRadius: 4,
                                ),
                                const SizedBox(height: 8),
                                _MobileLoginSkeleton._buildSkeletonInputBox(
                                  palette: palette,
                                  icon: Icons.lock_outline,
                                  hintWidth: 90,
                                  hasSuffix: true,
                                ),
                                const SizedBox(height: 18),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        DefensysSkeleton.box(
                                          width: 18,
                                          height: 18,
                                          borderRadius: 4,
                                        ),
                                        const SizedBox(width: 8),
                                        DefensysSkeleton.box(
                                          width: 90,
                                          height: 12,
                                          borderRadius: 4,
                                        ),
                                      ],
                                    ),
                                    DefensysSkeleton.box(
                                      width: 105,
                                      height: 12,
                                      borderRadius: 4,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                Container(
                                  height: 50,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: palette.action
                                        .withValues(alpha: 0.85),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  alignment: Alignment.center,
                                  child: Container(
                                    width: 70,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.4),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Web Footer Skeleton
                        DefensysShimmer(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              DefensysSkeleton.box(
                                width: 80,
                                height: 11,
                                borderRadius: 3,
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: palette.muted,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              DefensysSkeleton.box(
                                width: 80,
                                height: 11,
                                borderRadius: 3,
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: palette.muted,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              DefensysSkeleton.box(
                                width: 80,
                                height: 11,
                                borderRadius: 3,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
