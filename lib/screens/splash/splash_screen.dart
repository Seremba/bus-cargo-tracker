import 'dart:async';
import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  final Widget next;
  final Duration duration;

  const SplashScreen({
    super.key,
    required this.next,
    this.duration = const Duration(seconds: 2),
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  Timer? _t;

  static const _logoPath = 'assets/branding/jex_logistics.png';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Preload logo to avoid first-frame blink
    precacheImage(const AssetImage(_logoPath), context);
  }

  @override
  void initState() {
    super.initState();

    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fade = CurvedAnimation(parent: _c, curve: Curves.easeOut);

    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.90,
          end: 1.04,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 70,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.04,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
    ]).animate(_c);

    _c.forward();

    _t = Timer(widget.duration, () {
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => widget.next));
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    final logo = Image.asset(_logoPath, width: 190, fit: BoxFit.contain);

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        logo,
        const SizedBox(height: 22),
        SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(
              Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ],
    );

    return Scaffold(
      body: Container(
        color: Colors.white,
        alignment: Alignment.center,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: reduceMotion
                ? content
                : FadeTransition(
                    opacity: _fade,
                    child: ScaleTransition(scale: _scale, child: content),
                  ),
          ),
        ),
      ),
    );
  }
}
