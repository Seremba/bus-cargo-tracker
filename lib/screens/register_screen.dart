import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
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
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Create Account')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                const Text(
                  'Create Sender Account',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Register as a sender to track your cargo and receive updates.',
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    border: OutlineInputBorder(),
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
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Phone',
                    hintText: '07XXXXXXXX or 2567XXXXXXXX',
                    helperText: 'We will format your number automatically.',
                    border: OutlineInputBorder(),
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
                  obscureText: _hidePass,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Password',
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
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return 'Password required';
                    if (t.length < 6) return 'At least 6 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _confirmPassword,
                  obscureText: _hideConfirmPass,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _loading ? null : _submit(),
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: _hideConfirmPass
                          ? 'Show password'
                          : 'Hide password',
                      icon: Icon(
                        _hideConfirmPass
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () =>
                          setState(() => _hideConfirmPass = !_hideConfirmPass),
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
                const SizedBox(height: 18),

                ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create sender account'),
                ),
                const SizedBox(height: 10),

                TextButton(
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_loading) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_formKey.currentState!.validate()) return;

    final fullName = _name.text.trim();
    final phone = _phone.text.trim();
    final password = _password.text.trim();

    setState(() => _loading = true);

    try {
      final user = await AuthService.registerSender(
        fullName: fullName,
        phone: phone,
        password: password,
      );

      if (!mounted) return;

      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Registration failed ❌ (phone may already exist)'),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account created ✅ Please login')),
      );

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => LoginScreen(initialPhone: phone)),
        (_) => false,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to create account ❌')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
