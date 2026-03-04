import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/user_role.dart';
import '../services/auth_service.dart';
import '../services/outbound_queue_runner.dart';
import '../services/session_service.dart';
import '../services/phone_normalizer.dart';

import 'forgot_password_screen.dart';
import 'register_screen.dart';

import 'sender/sender_dashboard.dart';
import 'dashboards/staff_dashboard.dart';
import 'dashboards/driver_dashboard.dart';
import 'dashboards/admin_dashboard.dart';
import 'dashboards/desk_cargo_officer_dashboard.dart';

class LoginScreen extends StatefulWidget {
  final String? initialPhone;

  const LoginScreen({super.key, this.initialPhone});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  final FocusNode _passwordFocus = FocusNode();

  bool _loading = false;
  bool _hidePass = true;

  @override
  void initState() {
    super.initState();

    final init = widget.initialPhone?.trim() ?? '';
    if (init.isNotEmpty) {
      phoneController.text = PhoneNormalizer.displayUg(init);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _passwordFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    phoneController.dispose();
    passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _openForgotPassword() async {
    if (_loading) return;

    final returnedPhone = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
    );

    if (!mounted) return;

    final t = (returnedPhone ?? '').trim();
    if (t.isNotEmpty) {
      phoneController.text = PhoneNormalizer.displayUg(t);
      _passwordFocus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Login')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                const Text(
                  'Welcome back',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
                const SizedBox(height: 6),
                const Text('Login to continue managing and tracking cargo.'),
                const SizedBox(height: 14),

                TextFormField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Phone',
                    hintText: '07XXXXXXXX',
                    helperText: 'Use your phone number (UG or international).',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final raw = (value ?? '').trim();
                    if (raw.isEmpty) return 'Phone number is required';

                    final digits = PhoneNormalizer.digitsOnly(raw);
                    if (digits.length < 9) return 'Enter a valid phone number';
                    if (digits.length > 15) return 'Phone number too long';
                    if (RegExp(r'^0+$').hasMatch(digits)) {
                      return 'Enter a valid phone number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: passwordController,
                  focusNode: _passwordFocus,
                  obscureText: _hidePass,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _loading ? null : _handleLogin(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: _hidePass ? 'Show password' : 'Hide password',
                      icon: Icon(
                        _hidePass ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () => setState(() => _hidePass = !_hidePass),
                    ),
                  ),
                  validator: (value) {
                    final v = value?.trim() ?? '';
                    if (v.isEmpty) return 'Password is required';
                    if (v.length < 4) {
                      return 'Password must be at least 4 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),

                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  runSpacing: 6,
                  children: [
                    TextButton(
                      onPressed: _loading ? null : _openForgotPassword,
                      child: const Text('Forgot password?'),
                    ),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const RegisterScreen(),
                                ),
                              );
                            },
                      child: const Text('Create sender account'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: _loading ? null : _handleLogin,
                  child: _loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Login'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      final phone = phoneController.text.trim();
      final password = passwordController.text.trim();

      final user = await AuthService.loginByPhonePassword(
        phone: phone,
        password: password,
      );

      if (!mounted) return;

      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid phone/password ❌')),
        );
        return;
      }

      await SessionService.saveUser(user);

      OutboundQueueRunner.start();

      final Widget destination;
      switch (user.role) {
        case UserRole.sender:
          destination = const SenderDashboard();
          break;
        case UserRole.staff:
          destination = const StaffDashboard();
          break;
        case UserRole.driver:
          destination = const DriverDashboard();
          break;
        case UserRole.admin:
          destination = const AdminDashboard();
          break;
        case UserRole.deskCargoOfficer:
          destination = const DeskCargoOfficerDashboard();
          break;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => destination),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
