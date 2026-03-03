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

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, _goNext);
  }

  @override
  void dispose() {
    _timer?.cancel();
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
      // Safety: never crash on splash routing errors.
      // If something fails, we just show an empty screen briefly,
      // or you can set `next:` to LoginScreen from main.dart.
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
    return Scaffold(
      backgroundColor: const Color(0xFF6A1B9A),
      body: Center(
        child: Image.asset(
          widget.logoAssetPath,
          width: 180,
          height: 180,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.local_shipping, size: 120, color: Colors.white),
        ),
      ),
    );
  }
}
