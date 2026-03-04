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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Reset Password')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                const Text(
                  'Reset your password',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
                const SizedBox(height: 6),
                Text(
                  _otpSent
                      ? 'Enter the OTP you received and set a new password.'
                      : 'Enter your phone number and we will send you a reset OTP.',
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: _phone,
                  enabled: !_otpSent && !_loading, // ✅ lock phone once OTP sent
                  keyboardType: TextInputType.phone,
                  textInputAction:
                      _otpSent ? TextInputAction.next : TextInputAction.done,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Phone',
                    hintText: '07XXXXXXXX',
                    border: OutlineInputBorder(),
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
                ),

                const SizedBox(height: 12),

                if (_otpSent) ...[
                  TextFormField(
                    controller: _otp,
                    focusNode: _otpFocus,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'OTP',
                      border: OutlineInputBorder(),
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
                    obscureText: _hidePass,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _loading ? null : _resetPassword(),
                    decoration: InputDecoration(
                      labelText: 'New Password',
                      helperText: 'Minimum 6 characters.',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: _hidePass ? 'Show password' : 'Hide password',
                        icon: Icon(
                          _hidePass ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () => setState(() => _hidePass = !_hidePass),
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
                  const SizedBox(height: 8),
                ],

                const SizedBox(height: 16),

                if (!_otpSent) ...[
                  ElevatedButton(
                    onPressed: _loading ? null : _sendOtp,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: _loading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Send OTP'),
                  ),
                ] else ...[
                  ElevatedButton(
                    onPressed: _loading ? null : _resetPassword,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: _loading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Reset Password'),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => setState(() {
                              _otpSent = false;
                              _otp.clear();
                              _newPassword.clear();
                            }),
                    child: const Text('Back (send OTP again)'),
                  ),
                ],
              ],
            ),
          ),
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

        // ✅ auto-focus OTP field after UI rebuild
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
        Navigator.pop(context, display); // ✅ return phone to Login
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}