import 'package:flutter/material.dart';
import 'package:intl_phone_field/intl_phone_field.dart';

import '../services/auth_service.dart';
import '../services/phone_otp_service.dart';
import 'login_screen.dart';
import 'otp_verification_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _loading = false;
  bool _hidePass = true;
  bool _hideConfirmPass = true;

  // Full E.164 phone number built by IntlPhoneField
  String _fullPhone = '';

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.65);

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
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.person_add_alt_1, color: cs.primary),
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
                        'Create a sender account',
                        style: TextStyle(color: muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),

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
                    const Text(
                      'Create Sender Account',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Track your cargo and receive updates.',
                      style: TextStyle(color: muted),
                    ),
                    const SizedBox(height: 14),

                    // Full Name
                    TextFormField(
                      controller: _name,
                      enabled: !_loading,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.isEmpty) return 'Name required';
                        if (t.length < 2) return 'Enter full name';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    // ── International phone field ────────────────────────────
                    IntlPhoneField(
                      enabled: !_loading,
                      initialCountryCode: 'UG',
                      decoration: const InputDecoration(
                        labelText: 'Phone Number',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (phone) {
                        _fullPhone = phone.completeNumber;
                      },
                      onCountryChanged: (country) {
                        _fullPhone = '';
                      },
                      validator: (phone) {
                        if (phone == null || phone.number.trim().isEmpty) {
                          return 'Phone number required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    // Password
                    TextFormField(
                      controller: _password,
                      enabled: !_loading,
                      obscureText: _hidePass,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        helperText: 'Minimum 6 characters.',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip:
                              _hidePass ? 'Show password' : 'Hide password',
                          icon: Icon(
                            _hidePass
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: _loading
                              ? null
                              : () =>
                                    setState(() => _hidePass = !_hidePass),
                        ),
                      ),
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.isEmpty) return 'Password required';
                        if (t.length < 6) return 'At least 6 characters';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    // Confirm Password
                    TextFormField(
                      controller: _confirmPassword,
                      enabled: !_loading,
                      obscureText: _hideConfirmPass,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _loading ? null : _submit(),
                      decoration: InputDecoration(
                        labelText: 'Confirm Password',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock_reset_outlined),
                        suffixIcon: IconButton(
                          tooltip: _hideConfirmPass
                              ? 'Show password'
                              : 'Hide password',
                          icon: Icon(
                            _hideConfirmPass
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: _loading
                              ? null
                              : () => setState(
                                    () =>
                                        _hideConfirmPass = !_hideConfirmPass,
                                  ),
                        ),
                      ),
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.isEmpty) return 'Confirm your password';
                        if (t != _password.text.trim()) {
                          return 'Passwords do not match';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 14),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _loading ? null : _submit,
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
                            : const Icon(Icons.check_circle_outline),
                        label: Text(
                          _loading ? 'Creating…' : 'Create sender account',
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    Center(
                      child: TextButton(
                        onPressed: _loading
                            ? null
                            : () {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const LoginScreen(),
                                  ),
                                );
                              },
                        child: const Text('Already have an account? Login'),
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_fullPhone.isEmpty) {
      _toast('Please enter a valid phone number');
      return;
    }

    setState(() => _loading = true);

    try {
      final user = await AuthService.registerSender(
        fullName: _name.text,
        phone: _fullPhone,
        password: _password.text,
      );

      if (!mounted) return;

      if (user == null) {
        _toast('Phone already registered ❌');
        return;
      }

      try {
        await PhoneOtpService.generateAndSend(
          userId: user.id,
          phone: user.phone,
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Account created but SMS failed to send. '
                'Tap Resend on the next screen.',
              ),
            ),
          );
        }
      }

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(
            userId: user.id,
            phone: user.phone,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}