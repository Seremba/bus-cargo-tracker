import 'dart:async';
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
    this.logoAssetPath = 'assets/branding/jex_logistics_ai.png',
    this.duration = const Duration(seconds: 2),
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  bool _navigated = false;

  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    // Logo fades in
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.7, curve: Curves.easeIn),
    );

    // Logo scales up slightly as it fades in (subtle pop)
    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutBack),
      ),
    );

    _controller.forward();
    _timer = Timer(widget.duration, _goNext);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
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

    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => target));
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final logoSize = screenWidth * 0.65;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        // Radial gradient gives depth vs flat solid color
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.2,
            colors: [
              Color(0xFF8E24AA), // lighter purple at center
              Color(0xFF4A148C), // deep purple at edges
            ],
          ),
        ),
        child: Stack(
          children: [
            // Subtle decorative circle top-right
            Positioned(
              top: -60,
              right: -60,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.04),
                ),
              ),
            ),
            // Subtle decorative circle bottom-left
            Positioned(
              bottom: -80,
              left: -80,
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.04),
                ),
              ),
            ),

            // Main content — centered
            Center(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Logo
                      Image.asset(
                        widget.logoAssetPath,
                        width: logoSize,
                        height: logoSize,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.local_shipping,
                              size: logoSize * 0.5,
                              color: Colors.white,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'JEx Logistics',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Loading indicator — bottom of screen
            Positioned(
              bottom: 48,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white.withValues(alpha: 0.60),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Loading...',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.50),
                        fontSize: 12,
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
    );
  }
}
