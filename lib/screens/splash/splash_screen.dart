import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  final Future<Widget> Function()? nextBuilder;
  final Widget? next;
  final String logoAssetPath;
  final Duration duration;

  const SplashScreen({
    super.key,
    this.nextBuilder,
    this.next,
    this.logoAssetPath = 'assets/branding/UNEX_logistics.png',
    this.duration = const Duration(seconds: 3),
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  Timer? _timer;
  bool _navigated = false;

  // Logo animation
  late AnimationController _logoController;
  late Animation<double> _logoFade;
  late Animation<double> _logoScale;

  // Tagline animation
  late AnimationController _taglineController;
  late Animation<double> _taglineFade;
  late Animation<Offset> _taglineSlide;

  // Gold line animation
  late AnimationController _lineController;
  late Animation<double> _lineWidth;

  // Loading dots animation
  late AnimationController _dotsController;

  @override
  void initState() {
    super.initState();

    // Logo — fades + scales in
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _logoFade = CurvedAnimation(parent: _logoController, curve: Curves.easeIn);

    _logoScale = Tween<double>(begin: 0.80, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutBack),
    );

    // Gold underline expands after logo
    _lineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _lineWidth = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _lineController, curve: Curves.easeOut));

    // Tagline slides up after line
    _taglineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _taglineFade = CurvedAnimation(
      parent: _taglineController,
      curve: Curves.easeIn,
    );

    _taglineSlide = Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _taglineController, curve: Curves.easeOut),
        );

    // Loading dots — loops forever
    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    // Staggered sequence
    _logoController.forward().then((_) {
      _lineController.forward().then((_) {
        _taglineController.forward();
      });
    });

    _timer = Timer(widget.duration, _goNext);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _logoController.dispose();
    _lineController.dispose();
    _taglineController.dispose();
    _dotsController.dispose();
    super.dispose();
  }

  Future<void> _goNext() async {
    if (!mounted || _navigated) return;

    Widget target = const SizedBox.shrink();

    try {
      if (widget.nextBuilder != null) {
        target = await widget.nextBuilder!();
      } else if (widget.next != null) {
        target = widget.next!;
      }
    } catch (_) {
      target = widget.next ?? const SizedBox.shrink();
    }

    if (!mounted || _navigated) return;
    _navigated = true;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => target,
        transitionDuration: const Duration(milliseconds: 600),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final logoSize = screenWidth * 0.70; // was 0.55 — bigger logo

    // Navy + gold palette
    const navyDeep = Color(0xFF0D1B2A);
    const navyMid = Color(0xFF162032);
    const gold = Color(0xFFF5A623);
    const goldLight = Color(0xFFFFD580);

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [navyMid, navyDeep, Color(0xFF091422)],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // ── Geometric background detail — diagonal gold lines ──────────
            Positioned.fill(
              child: CustomPaint(painter: _GeometricPainter(gold: gold)),
            ),

            // ── Top-right glow ─────────────────────────────────────────────
            Positioned(
              top: -screenHeight * 0.15,
              right: -screenWidth * 0.2,
              child: Container(
                width: screenWidth * 0.7,
                height: screenWidth * 0.7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      gold.withValues(alpha: 0.08),
                      gold.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),

            // ── Bottom-left glow ───────────────────────────────────────────
            Positioned(
              bottom: -screenHeight * 0.1,
              left: -screenWidth * 0.2,
              child: Container(
                width: screenWidth * 0.6,
                height: screenWidth * 0.6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      gold.withValues(alpha: 0.05),
                      gold.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),

            // ── Main content ───────────────────────────────────────────────
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo with subtle gold glow
                  FadeTransition(
                    opacity: _logoFade,
                    child: ScaleTransition(
                      scale: _logoScale,
                      child: Container(
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: gold.withValues(alpha: 0.12),
                              blurRadius: 48,
                              spreadRadius: 12,
                            ),
                          ],
                        ),
                        child: Image.asset(
                          widget.logoAssetPath,
                          width: logoSize,
                          height: logoSize,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => _FallbackLogo(
                            size: logoSize,
                            gold: gold,
                            goldLight: goldLight,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 4),

                  // Expanding gold underline with glow
                  AnimatedBuilder(
                    animation: _lineWidth,
                    builder: (_, __) {
                      return Container(
                        width: logoSize * 0.55 * _lineWidth.value,
                        height: 2.5,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              gold.withValues(alpha: 0.0),
                              gold,
                              goldLight,
                              gold,
                              gold.withValues(alpha: 0.0),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: [
                            BoxShadow(
                              color: gold.withValues(alpha: 0.50),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 28),

                  // Tagline
                  FadeTransition(
                    opacity: _taglineFade,
                    child: SlideTransition(
                      position: _taglineSlide,
                      child: Column(
                        children: [
                          Text(
                            'FAST. RELIABLE. TRACKED.',
                            style: TextStyle(
                              color: gold.withValues(alpha: 0.90),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 3.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Kampala · Nairobi · Juba · Kigali · Goma',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.30),
                              fontSize: 10,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Loading dots — bottom ──────────────────────────────────────
            Positioned(
              bottom: 52,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _taglineFade,
                child: _LoadingDots(controller: _dotsController, gold: gold),
              ),
            ),

            // ── Version tag — very bottom ──────────────────────────────────
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _taglineFade,
                child: Text(
                  'v1.0',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.15),
                    fontSize: 10,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Fallback logo (no asset) ───────────────────────────────────────────────

class _FallbackLogo extends StatelessWidget {
  final double size;
  final Color gold;
  final Color goldLight;

  const _FallbackLogo({
    required this.size,
    required this.gold,
    required this.goldLight,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size * 0.35,
          height: size * 0.35,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [goldLight, gold]),
            boxShadow: [
              BoxShadow(
                color: gold.withValues(alpha: 0.40),
                blurRadius: 32,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Icon(
            Icons.local_shipping_rounded,
            size: size * 0.18,
            color: const Color(0xFF0D1B2A),
          ),
        ),
        const SizedBox(height: 20),
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [gold, goldLight, gold],
          ).createShader(bounds),
          child: Text(
            'JEx',
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.18,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
              height: 1,
            ),
          ),
        ),
        Text(
          'LOGISTICS',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: size * 0.055,
            fontWeight: FontWeight.w400,
            letterSpacing: 6,
          ),
        ),
      ],
    );
  }
}

// ── Animated loading dots ──────────────────────────────────────────────────

class _LoadingDots extends StatelessWidget {
  final AnimationController controller;
  final Color gold;

  const _LoadingDots({required this.controller, required this.gold});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) {
            // Each dot pulses offset from the others
            final phase = (controller.value - (i * 0.25)) % 1.0;
            final scale = 0.5 + 0.5 * math.sin(phase * math.pi).clamp(0.0, 1.0);
            final opacity = 0.25 + 0.75 * scale;

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: gold.withValues(alpha: opacity),
              ),
              transform: Matrix4.identity()..scale(0.7 + 0.3 * scale),
              transformAlignment: Alignment.center,
            );
          }),
        );
      },
    );
  }
}

// ── Geometric background painter ──────────────────────────────────────────

class _GeometricPainter extends CustomPainter {
  final Color gold;
  const _GeometricPainter({required this.gold});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = gold.withValues(alpha: 0.04)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Diagonal lines — top-left to bottom-right
    const spacing = 60.0;
    for (
      double offset = -size.height;
      offset < size.width + size.height;
      offset += spacing
    ) {
      canvas.drawLine(
        Offset(offset, 0),
        Offset(offset + size.height, size.height),
        paint,
      );
    }

    // Subtle corner triangle — top left
    final triPaint = Paint()
      ..color = gold.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;

    final triPath = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.35, 0)
      ..lineTo(0, size.height * 0.25)
      ..close();

    canvas.drawPath(triPath, triPaint);

    // Subtle corner triangle — bottom right
    final triPath2 = Path()
      ..moveTo(size.width, size.height)
      ..lineTo(size.width * 0.65, size.height)
      ..lineTo(size.width, size.height * 0.75)
      ..close();

    canvas.drawPath(triPath2, triPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
