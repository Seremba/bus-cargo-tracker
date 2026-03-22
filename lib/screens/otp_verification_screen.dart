import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/phone_otp_service.dart';
import 'login_screen.dart';

/// S3: Sender phone OTP verification screen.
///
/// Shown immediately after successful sender registration.
/// The OTP has already been sent by [RegisterScreen] before navigation here.
///
/// [userId]    — the newly registered user's ID
/// [phone]     — normalized phone number (for display and resend)
class OtpVerificationScreen extends StatefulWidget {
  final String userId;
  final String phone;

  const OtpVerificationScreen({
    super.key,
    required this.userId,
    required this.phone,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final _controllers = List.generate(6, (_) => TextEditingController());
  final _focusNodes = List.generate(6, (_) => FocusNode());

  bool _loading = false;
  bool _resending = false;
  String? _error;

  // Resend cooldown
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  // OTP expiry countdown
  int _expirySeconds = PhoneOtpService.otpTtlSeconds;
  Timer? _expiryTimer;

  @override
  void initState() {
    super.initState();
    _startExpiryCountdown();
  }

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    for (final f in _focusNodes) f.dispose();
    _cooldownTimer?.cancel();
    _expiryTimer?.cancel();
    super.dispose();
  }

  void _startExpiryCountdown() {
    _expiryTimer?.cancel();
    setState(() => _expirySeconds = PhoneOtpService.otpTtlSeconds);
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _expirySeconds--;
        if (_expirySeconds <= 0) {
          _expirySeconds = 0;
          t.cancel();
        }
      });
    });
  }

  void _startResendCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _resendCooldown = 60);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _resendCooldown--;
        if (_resendCooldown <= 0) {
          _resendCooldown = 0;
          t.cancel();
        }
      });
    });
  }

  String get _enteredOtp =>
      _controllers.map((c) => c.text.trim()).join();

  bool get _otpExpired => _expirySeconds <= 0;

  String _fmtExpiry(int s) {
    if (s <= 0) return 'Expired';
    final m = s ~/ 60;
    final sec = s % 60;
    return m > 0
        ? '$m:${sec.toString().padLeft(2, '0')}'
        : '${sec}s';
  }

  void _onDigitInput(int index, String value) {
    if (value.length == 6) {
      // Handle paste of full OTP
      for (int i = 0; i < 6; i++) {
        _controllers[i].text = value[i];
      }
      _focusNodes[5].requestFocus();
      _verify();
      return;
    }

    if (value.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }

    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }

    // Auto-submit when all 6 digits entered
    if (_enteredOtp.length == 6) {
      _verify();
    }
  }

  Future<void> _verify() async {
    final otp = _enteredOtp;
    if (otp.length != 6) {
      setState(() => _error = 'Enter all 6 digits');
      return;
    }

    if (_otpExpired) {
      setState(() => _error = 'OTP expired. Tap Resend to get a new one.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await PhoneOtpService.verifyOtp(
        userId: widget.userId,
        otp: otp,
      );

      if (!mounted) return;

      switch (result) {
        case OtpVerifyResult.success:
          _expiryTimer?.cancel();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Phone verified ✅ You can now log in'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (_) => false,
          );
          break;

        case OtpVerifyResult.wrongOtp:
          setState(() => _error = 'Wrong OTP. Check and try again.');
          _clearInputs();
          break;

        case OtpVerifyResult.expired:
          setState(() => _error = 'OTP expired. Tap Resend to get a new one.');
          _clearInputs();
          break;

        case OtpVerifyResult.tooManyAttempts:
          setState(
            () => _error = 'Too many attempts. Tap Resend to get a new OTP.',
          );
          _clearInputs();
          break;

        case OtpVerifyResult.notFound:
          setState(() => _error = 'OTP not found. Tap Resend.');
          break;
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    if (_resendCooldown > 0 || _resending) return;

    setState(() {
      _resending = true;
      _error = null;
    });

    try {
      await PhoneOtpService.generateAndSend(
        userId: widget.userId,
        phone: widget.phone,
      );

      if (!mounted) return;

      _clearInputs();
      _startExpiryCountdown();
      _startResendCooldown();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New OTP sent via SMS')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Failed to resend. Try again.');
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  void _clearInputs() {
    for (final c in _controllers) c.clear();
    _focusNodes[0].requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.60);

    // Show last 4 digits of phone for privacy
    final displayPhone = widget.phone.length >= 4
        ? '••••${widget.phone.substring(widget.phone.length - 4)}'
        : widget.phone;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        title: const Text(''),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.verified_outlined, color: cs.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'UNEX LOGISTICS',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Verify your phone number',
                        style: TextStyle(color: muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.60),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    'Enter verification code',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'We sent a 6-digit code to $displayPhone via SMS.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted),
                  ),
                  const SizedBox(height: 6),

                  // Expiry countdown
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      _otpExpired
                          ? 'Code expired — tap Resend'
                          : 'Expires in ${_fmtExpiry(_expirySeconds)}',
                      key: ValueKey(_otpExpired),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _otpExpired
                            ? cs.error
                            : _expirySeconds < 60
                            ? Colors.orange.shade700
                            : Colors.green.shade700,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 6-digit OTP input boxes
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(6, (i) {
                      return Container(
                        width: 44,
                        height: 52,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        child: TextFormField(
                          controller: _controllers[i],
                          focusNode: _focusNodes[i],
                          enabled: !_loading && !_otpExpired,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          maxLength: i == 0 ? 6 : 1,
                          // allow paste on first box
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                          decoration: InputDecoration(
                            counterText: '',
                            contentPadding: EdgeInsets.zero,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(
                                color: cs.primary,
                                width: 2,
                              ),
                            ),
                          ),
                          onChanged: (v) => _onDigitInput(i, v),
                        ),
                      );
                    }),
                  ),

                  const SizedBox(height: 12),

                  // Error message
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: cs.error,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),

                  const SizedBox(height: 8),

                  // Verify button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: (_loading || _otpExpired) ? null : _verify,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: _loading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_circle_outline),
                      label: Text(_loading ? 'Verifying…' : 'Verify'),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Resend button
                  TextButton.icon(
                    onPressed:
                        (_resendCooldown > 0 || _resending) ? null : _resend,
                    icon: _resending
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 16),
                    label: Text(
                      _resendCooldown > 0
                          ? 'Resend in ${_resendCooldown}s'
                          : _resending
                          ? 'Sending…'
                          : 'Resend code',
                      style: TextStyle(
                        color: _resendCooldown > 0 ? muted : cs.primary,
                      ),
                    ),
                  ),

                  const SizedBox(height: 4),

                  // Skip for now (rare case — AT sandbox not working)
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () {
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const LoginScreen(),
                              ),
                              (_) => false,
                            );
                          },
                    child: Text(
                      'Skip for now',
                      style: TextStyle(
                        fontSize: 12,
                        color: muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}