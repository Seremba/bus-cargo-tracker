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

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // Fade animation
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );

    _fadeController.forward();

    _timer = Timer(widget.duration, _goNext);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _fadeController.dispose();
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
      MaterialPageRoute(builder: (_) => target),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    // Logo occupies ~60% of screen width
    final logoSize = screenWidth * 0.6;

    return Scaffold(
      backgroundColor: const Color(0xFF6A1B9A),
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Image.asset(
            widget.logoAssetPath,
            width: logoSize,
            height: logoSize,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.local_shipping,
              size: 160,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}