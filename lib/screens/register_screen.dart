import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/phone_normalizer.dart';
import 'login_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _loading = false;
  bool _hidePass = true;
  bool _hideConfirmPass = true;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
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

  String _digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  /// ✅ Normalize Uganda phone to a single canonical format:
  /// Store as "2567XXXXXXXX" or "2563XXXXXXXX" (no plus sign).
  String _normalizePhoneUg(String raw) {
    var d = _digitsOnly(raw.trim());
    if (d.isEmpty) return '';

    // 07XXXXXXXX -> 2567XXXXXXXX
    if (d.startsWith('0') && d.length == 10) {
      d = '256${d.substring(1)}';
    }

    // 7XXXXXXXX -> 2567XXXXXXXX (if user omits leading 0)
    if (!d.startsWith('256') &&
        d.length == 9 &&
        (d.startsWith('7') || d.startsWith('3'))) {
      d = '256$d';
    }

    return d;
  }

  bool _isValidUgMobileCanonical(String canonical) {
    if (canonical.length != 12) return false;
    if (!canonical.startsWith('256')) return false;

    final after = canonical.substring(3);
    if (after.length != 9) return false;
    if (!(after.startsWith('7') || after.startsWith('3'))) return false;

    return true;
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
            // ✅ Brand header (matches Login)
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
                        'Bebeto Cargo',
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

            // ✅ Form container (structure + calm)
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

                    TextFormField(
                      controller: _phone,
                      enabled: !_loading,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(15),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Phone',
                        hintText: '07XXXXXXXX or 2567XXXXXXXX',
                        helperText: 'We will format your number automatically.',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                      validator: (v) {
                        final canonical = _normalizePhoneUg(v ?? '');
                        if (canonical.isEmpty) return 'Phone required';
                        if (!_isValidUgMobileCanonical(canonical)) {
                          return 'Enter a valid UG phone (07.. or 2567..)';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

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
                          tooltip: _hidePass
                              ? 'Show password'
                              : 'Hide password',
                          icon: Icon(
                            _hidePass ? Icons.visibility : Icons.visibility_off,
                          ),
                          onPressed: _loading
                              ? null
                              : () => setState(() => _hidePass = !_hidePass),
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
                                  () => _hideConfirmPass = !_hideConfirmPass,
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
    if (_loading) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_formKey.currentState!.validate()) return;

    final fullName = _name.text.trim();
    final rawPhone = _phone.text.trim();
    final canonical = _normalizePhoneUg(rawPhone);
    final password = _password.text.trim();

    setState(() => _loading = true);

    try {
      final user = await AuthService.registerSender(
        fullName: fullName,
        phone: canonical, // ✅ store canonical
        password: password,
      );

      if (!mounted) return;

      if (user == null) {
        _toast('Registration failed ❌ (phone may already exist)');
        return;
      }

      _toast('Account created ✅ Please login');

      final displayPhone = PhoneNormalizer.displayUg(canonical);

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => LoginScreen(initialPhone: displayPhone),
        ),
        (_) => false,
      );
    } catch (_) {
      if (!mounted) return;
      _toast('Failed to create account ❌');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
