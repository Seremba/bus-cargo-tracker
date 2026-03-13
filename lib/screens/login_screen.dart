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

  // ✅ NEW: inline dropdown state
  bool _showCreateHint = false;

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

  void _toast(String msg) {
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(content: Text(msg)));
  }

  void _toggleCreateHint() {
    if (_loading) return;
    setState(() => _showCreateHint = !_showCreateHint);
  }

  Future<void> _goToRegister() async {
    if (_loading) return;

    setState(() => _showCreateHint = false);

    final returnedPhone = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
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
                  child: Icon(Icons.local_shipping_outlined, color: cs.primary),
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
                      Text('Login to continue', style: TextStyle(color: muted)),
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
                      'Welcome back',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Manage and track cargo with your account.',
                      style: TextStyle(color: muted),
                    ),
                    const SizedBox(height: 14),

                    TextFormField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      enabled: !_loading,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(15),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Phone',
                        hintText: 'e.g. 0700000000 or 2567XXXXXXXX',
                        helperText: 'UG or international format.',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                      validator: (value) {
                        final raw = (value ?? '').trim();
                        if (raw.isEmpty) return 'Phone number is required';

                        final digits = PhoneNormalizer.digitsOnly(raw);
                        if (digits.length < 9)
                          return 'Enter a valid phone number';
                        if (digits.length > 15) return 'Phone number too long';
                        if (RegExp(r'^0+$').hasMatch(digits)) {
                          return 'Enter a valid phone number';
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                    ),
                    const SizedBox(height: 12),

                    TextFormField(
                      controller: passwordController,
                      focusNode: _passwordFocus,
                      obscureText: _hidePass,
                      enabled: !_loading,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _loading ? null : _handleLogin(),
                      decoration: InputDecoration(
                        labelText: 'Password',
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
                      validator: (value) {
                        final v = value?.trim() ?? '';
                        if (v.isEmpty) return 'Password is required';
                        if (v.length < 4) {
                          return 'Password must be at least 4 characters';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 10),

                    // ✅ Wrap avoids overflow on small screens/font sizes
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      runSpacing: 6,
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: _loading ? null : _openForgotPassword,
                          child: const Text('Forgot password?'),
                        ),
                        TextButton.icon(
                          onPressed: _loading ? null : _toggleCreateHint,
                          icon: Icon(
                            _showCreateHint
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            size: 18,
                          ),
                          label: const Text('New sender? Create account'),
                        ),
                      ],
                    ),

                    // ✅ Inline "dropdown" panel (animated)
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child: !_showCreateHint
                          ? const SizedBox.shrink()
                          : Container(
                              key: const ValueKey('createHintPanel'),
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest.withValues(
                                  alpha: 0.35,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: cs.outlineVariant.withValues(
                                    alpha: 0.60,
                                  ),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    size: 18,
                                    color: cs.primary,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Only senders can create accounts here.',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: cs.onSurface,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Staff accounts are created by the administrator.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: muted,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Row(
                                          children: [
                                            TextButton(
                                              onPressed: _loading
                                                  ? null
                                                  : () => setState(
                                                      () => _showCreateHint =
                                                          false,
                                                    ),
                                              child: const Text('Cancel'),
                                            ),
                                            const Spacer(),
                                            ElevatedButton(
                                              onPressed: _loading
                                                  ? null
                                                  : _goToRegister,
                                              child: const Text('Continue'),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),

                    const SizedBox(height: 10),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: _loading ? null : _handleLogin,
                        icon: _loading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.login),
                        label: Text(_loading ? 'Logging in…' : 'Login'),
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
        _toast('Invalid phone/password ❌');
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
