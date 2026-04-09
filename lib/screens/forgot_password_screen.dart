import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/password_reset_service.dart';
import '../services/phone_normalizer.dart';
import 'set_new_password_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  /// Optional phone number to pre-fill. Used when redirecting a shell
  /// account user (staff/driver/desk) to set their password for the
  /// first time via OTP before they can login.
  final String? initialPhone;

  const ForgotPasswordScreen({super.key, this.initialPhone});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  final FocusNode _otpFocus = FocusNode();

  bool _loading = false;
  bool _otpSent = false;

  @override
  void initState() {
    super.initState();
    final init = widget.initialPhone?.trim() ?? '';
    if (init.isNotEmpty) {
      _phone.text = init;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _sendOtp();
      });
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    _otp.dispose();
    _otpFocus.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.65);
    final isFirstLogin = (widget.initialPhone ?? '').trim().isNotEmpty;

    final displayPhone = _phone.text.trim().isEmpty
        ? ''
        : PhoneNormalizer.displayUg(_phone.text.trim());

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
            // ── Header ──
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isFirstLogin
                        ? Icons.key_outlined
                        : Icons.lock_reset_outlined,
                    color: cs.primary,
                  ),
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
                        isFirstLogin ? 'Set your password' : 'Reset password',
                        style: TextStyle(color: muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // First-login info banner
            if (isFirstLogin) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: cs.primary.withValues(alpha: 0.20),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 18, color: cs.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your account was created by an administrator. '
                        'Set your own password using the OTP sent to your phone.',
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withValues(alpha: 0.80),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 18),

            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.60),
                ),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _otpSent
                          ? 'Enter your OTP'
                          : isFirstLogin
                              ? 'Set your password'
                              : 'Reset your password',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _otpSent
                          ? 'Enter the 6-digit code sent to your phone.'
                          : isFirstLogin
                              ? 'An OTP will be sent to your registered phone number.'
                              : 'Enter your phone number and we\'ll send you a reset OTP.',
                      style: TextStyle(color: muted),
                    ),

                    // OTP sent confirmation banner
                    if (_otpSent && displayPhone.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: cs.primary.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.sms_outlined,
                                size: 18, color: cs.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'OTP sent to $displayPhone',
                                style: TextStyle(
                                  color: cs.onSurface.withValues(alpha: 0.85),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 14),

                    // Phone field — locked once OTP sent
                    TextFormField(
                      controller: _phone,
                      enabled: !_otpSent && !_loading && !isFirstLogin,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(15),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Phone',
                        hintText: '07XXXXXXXX or +2567XXXXXXXX',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                      validator: (v) {
                        final raw = (v ?? '').trim();
                        if (raw.isEmpty) return 'Phone is required';
                        final digits = PhoneNormalizer.digitsOnly(raw);
                        if (digits.length < 9) return 'Enter a valid phone number';
                        if (digits.length > 15) return 'Phone number too long';
                        if (RegExp(r'^0+$').hasMatch(digits)) {
                          return 'Enter a valid phone number';
                        }
                        if (!_otpSent) {
                          final msg = PhoneNormalizer.normalizeForMessaging(raw);
                          if (msg.isEmpty) {
                            return 'Enter a message-ready number (07.. or include country code).';
                          }
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) =>
                          _otpSent ? null : (_loading ? null : _sendOtp()),
                    ),

                    // OTP field — shown after OTP is sent
                    if (_otpSent) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _otp,
                        focusNode: _otpFocus,
                        enabled: !_loading,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'OTP Code',
                          hintText: '6-digit code',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.password_outlined),
                        ),
                        onFieldSubmitted: (_) =>
                            _loading ? null : _verifyOtp(),
                        validator: (v) {
                          if (!_otpSent) return null;
                          final t = (v ?? '').trim();
                          if (t.isEmpty) return 'OTP is required';
                          if (t.length < 6) return 'Enter the full 6-digit OTP';
                          return null;
                        },
                      ),
                    ],

                    const SizedBox(height: 16),

                    // Action button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _loading
                            ? null
                            : _otpSent
                                ? _verifyOtp
                                : _sendOtp,
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                _otpSent
                                    ? Icons.arrow_forward
                                    : Icons.send,
                              ),
                        label: Text(
                          _loading
                              ? (_otpSent ? 'Verifying…' : 'Sending…')
                              : (_otpSent ? 'Verify OTP' : 'Send OTP'),
                        ),
                      ),
                    ),

                    // Resend / back option
                    if (_otpSent) ...[
                      const SizedBox(height: 10),
                      Center(
                        child: TextButton(
                          onPressed: _loading
                              ? null
                              : () => setState(() {
                                    _otpSent = false;
                                    _otp.clear();
                                  }),
                          child: const Text('Resend OTP'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendOtp() async {
    if (_loading) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final res = await PasswordResetService.requestOtp(
        rawPhone: _phone.text.trim(),
      );

      if (!mounted) return;
      _snack(res.message);

      if (res.ok) {
        setState(() => _otpSent = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _otpFocus.requestFocus();
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyOtp() async {
    if (_loading) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final res = await PasswordResetService.verifyOtpOnly(
        rawPhone: _phone.text.trim(),
        otp: _otp.text.trim(),
      );

      if (!mounted) return;

      if (!res.ok) {
        _snack(res.message);
        return;
      }

      // OTP verified — navigate to set new password screen
      final phone = _phone.text.trim();
      final returnedPhone = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => SetNewPasswordScreen(rawPhone: phone),
        ),
      );

      if (!mounted) return;
      // Pop back to login with the phone so it can be pre-filled
      Navigator.pop(context, returnedPhone ?? phone);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}