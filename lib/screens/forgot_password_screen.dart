import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/password_reset_service.dart';
import '../services/phone_normalizer.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();

  final _phone = TextEditingController();
  final _otp = TextEditingController();
  final _newPassword = TextEditingController();

  final FocusNode _otpFocus = FocusNode();
  final FocusNode _newPassFocus = FocusNode();

  bool _loading = false;
  bool _otpSent = false;
  bool _hidePass = true;

  @override
  void dispose() {
    _phone.dispose();
    _otp.dispose();
    _newPassword.dispose();
    _otpFocus.dispose();
    _newPassFocus.dispose();
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
            // ✅ Brand header (consistent)
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.lock_reset_outlined, color: cs.primary),
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
                        'Reset password',
                        style: TextStyle(color: muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // ✅ Form container
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
                      _otpSent ? 'Enter OTP and new password' : 'Reset your password',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _otpSent
                          ? 'Enter the OTP you received and choose a new password.'
                          : 'Enter your phone number and we will send you a reset OTP.',
                      style: TextStyle(color: muted),
                    ),

                    // ✅ little hint after OTP sent
                    if (_otpSent && displayPhone.isNotEmpty) ...[
                      const SizedBox(height: 8),
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

                    TextFormField(
                      controller: _phone,
                      enabled: !_otpSent && !_loading, // ✅ lock once OTP sent
                      keyboardType: TextInputType.phone,
                      textInputAction:
                          _otpSent ? TextInputAction.next : TextInputAction.done,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(15),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Phone',
                        hintText: '07XXXXXXXX or 2567XXXXXXXX',
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

                        // Only require "message-ready" when sending OTP
                        if (!_otpSent) {
                          final msg = PhoneNormalizer.normalizeForMessaging(raw);
                          if (msg.isEmpty) {
                            return 'Enter a message-ready number (07.. or include country code).';
                          }
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) => _otpSent
                          ? _otpFocus.requestFocus()
                          : (_loading ? null : _sendOtp()),
                    ),

                    const SizedBox(height: 12),

                    if (_otpSent) ...[
                      TextFormField(
                        controller: _otp,
                        focusNode: _otpFocus,
                        enabled: !_loading,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(8),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'OTP',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.password_outlined),
                        ),
                        onFieldSubmitted: (_) {
                          if (_loading) return;
                          _newPassFocus.requestFocus();
                        },
                        validator: (v) {
                          if (!_otpSent) return null;
                          final t = (v ?? '').trim();
                          if (t.isEmpty) return 'OTP is required';
                          if (t.length < 4) return 'Enter a valid OTP';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      TextFormField(
                        controller: _newPassword,
                        focusNode: _newPassFocus,
                        enabled: !_loading,
                        obscureText: _hidePass,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) =>
                            _loading ? null : _resetPassword(),
                        decoration: InputDecoration(
                          labelText: 'New Password',
                          helperText: 'Minimum 6 characters.',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _hidePass ? 'Show password' : 'Hide password',
                            icon: Icon(
                              _hidePass ? Icons.visibility : Icons.visibility_off,
                            ),
                            onPressed: _loading
                                ? null
                                : () => setState(() => _hidePass = !_hidePass),
                          ),
                        ),
                        validator: (v) {
                          if (!_otpSent) return null;
                          final t = (v ?? '').trim();
                          if (t.isEmpty) return 'New password is required';
                          if (t.length < 6) return 'At least 6 characters';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                    ],

                    const SizedBox(height: 6),

                    // ✅ Buttons
                    if (!_otpSent) ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _loading ? null : _sendOtp,
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
                              : const Icon(Icons.send),
                          label: Text(_loading ? 'Sending…' : 'Send OTP'),
                        ),
                      ),
                    ] else ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _loading ? null : _resetPassword,
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
                              : const Icon(Icons.lock_reset),
                          label: Text(_loading ? 'Resetting…' : 'Reset Password'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: TextButton(
                          onPressed: _loading
                              ? null
                              : () => setState(() {
                                    _otpSent = false;
                                    _otp.clear();
                                    _newPassword.clear();
                                  }),
                          child: const Text('Back (send OTP again)'),
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

  Future<void> _resetPassword() async {
    if (_loading) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final res = await PasswordResetService.verifyOtpAndResetPassword(
        rawPhone: _phone.text.trim(),
        otp: _otp.text.trim(),
        newPassword: _newPassword.text.trim(),
      );

      _snack(res.message);

      if (res.ok) {
        final display = PhoneNormalizer.displayUg(_phone.text.trim());
        Navigator.pop(context, display); // 
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}