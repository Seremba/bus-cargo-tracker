import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/phone_otp_service.dart';
import 'login_screen.dart';
import 'otp_verification_screen.dart';

// ── Country definitions ────────────────────────────────────────────────────
class _Country {
  final String name;
  final String flag;
  final String dialCode;
  final String placeholder;

  const _Country({
    required this.name,
    required this.flag,
    required this.dialCode,
    required this.placeholder,
  });
}

const List<_Country> _countries = [
  _Country(
    name: 'Uganda',
    flag: '🇺🇬',
    dialCode: '+256',
    placeholder: '7XXXXXXXX',
  ),
  _Country(
    name: 'Kenya',
    flag: '🇰🇪',
    dialCode: '+254',
    placeholder: '7XXXXXXXX',
  ),
  _Country(
    name: 'South Sudan',
    flag: '🇸🇸',
    dialCode: '+211',
    placeholder: '9XXXXXXXX',
  ),
  _Country(
    name: 'Rwanda',
    flag: '🇷🇼',
    dialCode: '+250',
    placeholder: '7XXXXXXXX',
  ),
  _Country(
    name: 'DR Congo',
    flag: '🇨🇩',
    dialCode: '+243',
    placeholder: '8XXXXXXXX',
  ),
];

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

  // Default to Uganda
  _Country _selectedCountry = _countries.first;

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

  /// Builds full E.164 number from selected country + entered digits.
  /// e.g. +256 + 704811862 → +256704811862
  String _buildE164() {
    final digits = _digitsOnly(_phone.text.trim());
    if (digits.isEmpty) return '';
    // Remove leading zero if present (e.g. 0704... → 704...)
    final cleaned = digits.startsWith('0') ? digits.substring(1) : digits;
    return '${_selectedCountry.dialCode}$cleaned';
  }

  bool _isValidPhone() {
    final e164 = _buildE164();
    // E.164 format: + followed by 7-15 digits
    return RegExp(r'^\+\d{7,15}$').hasMatch(e164);
  }

  Future<void> _showCountryPicker() async {
    final selected = await showModalBottomSheet<_Country>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Select Country',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 8),
            ...List.generate(_countries.length, (i) {
              final c = _countries[i];
              return ListTile(
                leading: Text(c.flag, style: const TextStyle(fontSize: 24)),
                title: Text(c.name),
                trailing: Text(
                  c.dialCode,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
                onTap: () => Navigator.pop(context, c),
              );
            }),
            const SizedBox(height: 16),
          ],
        );
      },
    );

    if (selected != null) {
      setState(() {
        _selectedCountry = selected;
        _phone.clear();
      });
    }
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

                    // ── Phone with country code picker ──────────────────────
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Country code button
                        GestureDetector(
                          onTap: _loading ? null : _showCountryPicker,
                          child: Container(
                            height: 56,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: cs.outline.withValues(alpha: 0.6),
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _selectedCountry.flag,
                                  style: const TextStyle(fontSize: 20),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _selectedCountry.dialCode,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Icon(
                                  Icons.arrow_drop_down,
                                  color: cs.onSurface.withValues(alpha: 0.5),
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Phone number input
                        Expanded(
                          child: TextFormField(
                            controller: _phone,
                            enabled: !_loading,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.next,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(12),
                            ],
                            decoration: InputDecoration(
                              labelText: 'Phone Number',
                              hintText: _selectedCountry.placeholder,
                              helperText:
                                  'Without leading 0 or country code',
                              border: const OutlineInputBorder(),
                            ),
                            validator: (v) {
                              if ((v ?? '').trim().isEmpty) {
                                return 'Phone required';
                              }
                              if (!_isValidPhone()) {
                                return 'Enter a valid phone number';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
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
                                    () => _hideConfirmPass =
                                        !_hideConfirmPass,
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

    setState(() => _loading = true);

    try {
      // Build full E.164 phone number with country code
      final fullPhone = _buildE164();

      final user = await AuthService.registerSender(
        fullName: _name.text,
        phone: fullPhone,
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