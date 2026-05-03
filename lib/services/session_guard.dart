import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/session.dart';
import '../../services/session_service.dart';
import '../screens/login_screen.dart';

class SessionGuard extends StatefulWidget {
  final Widget child;
  const SessionGuard({super.key, required this.child});

  @override
  State<SessionGuard> createState() => _SessionGuardState();
}

class _SessionGuardState extends State<SessionGuard>
    with WidgetsBindingObserver {
  Timer? _ticker;
  bool _showingWarning = false;

  // How often to poll for expiry while app is foregrounded
  static const _pollInterval = Duration(seconds: 30);

  // How long the warning overlay stays before auto-logout
  static const _warningDuration = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Delay the first expiry check by 3 seconds to allow the session to
    // fully establish after login or restore before we start polling.
    // Without this delay, the ticker could fire while lastActivityAt is
    // still null (between SessionService.saveUser() and the first touch()),
    // causing Session.isExpired to return true and immediately logging the
    // user out right after a successful login.
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      _checkExpiry();
      _startTicker();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  // Re-check on app resume (e.g. user switches back from another app)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkExpiry();
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(_pollInterval, (_) => _checkExpiry());
  }

  void _checkExpiry() {
    if (!mounted) return;
    if (_showingWarning) return;
    if (Session.isExpired) {
      _triggerWarning();
    }
  }

  Future<void> _triggerWarning() async {
    if (_showingWarning) return;
    setState(() => _showingWarning = true);

    // Auto-logout after warning duration
    await Future.delayed(_warningDuration);

    // Widget may have been disposed during the delay
    if (!mounted) return;
    await _logout();
  }

  Future<void> _logout() async {
    await SessionService.clear();
    if (!mounted) return;
    setState(() => _showingWarning = false);

    // Capture the navigator before any async gap to avoid
    // "Navigator operation requested with a context that does not include a Navigator"
    final navigator = Navigator.maybeOf(context, rootNavigator: true);
    if (navigator == null) return;

    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  // Called by user interactions anywhere in the subtree
  void _onUserActivity() {
    if (_showingWarning) return;
    SessionService.touch();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _onUserActivity(),
      child: Stack(
        children: [widget.child, if (_showingWarning) _warningOverlay()],
      ),
    );
  }

  Widget _warningOverlay() {
    return Positioned.fill(
      child: Material(
        color: Colors.black87,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.lock_clock_outlined,
                    color: Colors.white,
                    size: 56,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Session Expired',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'You have been inactive for too long.\nLogging out for security.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 28),
                  // countdown visual
                  _CountdownBar(
                    duration: _warningDuration,
                    color: Colors.orangeAccent,
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                    ),
                    onPressed: _logout,
                    child: const Text('Log out now'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Simple animated progress bar that counts down the warning duration
class _CountdownBar extends StatefulWidget {
  final Duration duration;
  final Color color;
  const _CountdownBar({required this.duration, required this.color});

  @override
  State<_CountdownBar> createState() => _CountdownBarState();
}

class _CountdownBarState extends State<_CountdownBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: 1.0 - _ctrl.value,
          minHeight: 6,
          backgroundColor: Colors.white24,
          valueColor: AlwaysStoppedAnimation(widget.color),
        ),
      ),
    );
  }
}