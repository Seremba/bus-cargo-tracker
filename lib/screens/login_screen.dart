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
    final muted = cs.onSurface.withValues(alpha: 0.55);
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      // No AppBar — reclaim the space for vertical centering
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            // Ensure content fills screen height so card centers nicely
            constraints: BoxConstraints(
              minHeight:
                  screenHeight -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 32),

                // ── Branding header ───────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.local_shipping_outlined,
                        color: cs.primary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bebeto Cargo',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: cs.onSurface,
                            height: 1.1,
                          ),
                        ),
                        Text(
                          'Cargo tracking & management',
                          style: TextStyle(fontSize: 13, color: muted),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 28),

                // ── Login card ────────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.60),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Card header
                        const Text(
                          'Welcome back',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 22,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Sign in to manage and track your cargo.',
                          style: TextStyle(color: muted, fontSize: 13),
                        ),

                        const SizedBox(height: 20),

                        // Phone field
                        TextFormField(
                          controller: phoneController,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          enabled: !_loading,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(15),
                          ],
                          decoration: InputDecoration(
                            labelText: 'Phone',
                            hintText: 'e.g. 0700000000',
                            helperText: 'UG or international format.',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.phone_outlined),
                            filled: true,
                            fillColor: cs.surfaceContainerHighest.withValues(
                              alpha: 0.35,
                            ),
                          ),
                          validator: (value) {
                            final raw = (value ?? '').trim();
                            if (raw.isEmpty) return 'Phone number is required';
                            final digits = PhoneNormalizer.digitsOnly(raw);
                            if (digits.length < 9) {
                              return 'Enter a valid phone number';
                            }
                            if (digits.length > 15) {
                              return 'Phone number too long';
                            }
                            if (RegExp(r'^0+$').hasMatch(digits)) {
                              return 'Enter a valid phone number';
                            }
                            return null;
                          },
                          onFieldSubmitted: (_) =>
                              _passwordFocus.requestFocus(),
                        ),

                        const SizedBox(height: 14),

                        // Password field
                        TextFormField(
                          controller: passwordController,
                          focusNode: _passwordFocus,
                          obscureText: _hidePass,
                          enabled: !_loading,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) =>
                              _loading ? null : _handleLogin(),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.lock_outline),
                            filled: true,
                            fillColor: cs.surfaceContainerHighest.withValues(
                              alpha: 0.35,
                            ),
                            suffixIcon: IconButton(
                              tooltip: _hidePass
                                  ? 'Show password'
                                  : 'Hide password',
                              icon: Icon(
                                _hidePass
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              onPressed: _loading
                                  ? null
                                  : () =>
                                        setState(() => _hidePass = !_hidePass),
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

                        // Forgot password — smaller, right-aligned, muted
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: muted,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 4,
                              ),
                              textStyle: const TextStyle(fontSize: 13),
                            ),
                            onPressed: _loading ? null : _openForgotPassword,
                            child: const Text('Forgot password?'),
                          ),
                        ),

                        const SizedBox(height: 4),

                        // Login button with spinner
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: _loading ? null : _handleLogin,
                            child: _loading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.login, size: 20),
                                      SizedBox(width: 8),
                                      Text(
                                        'Login',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Divider before create account
                        Row(
                          children: [
                            Expanded(
                              child: Divider(
                                color: cs.outlineVariant.withValues(alpha: 0.5),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: Text(
                                'New here?',
                                style: TextStyle(fontSize: 12, color: muted),
                              ),
                            ),
                            Expanded(
                              child: Divider(
                                color: cs.outlineVariant.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // Create account — outlined button, clear CTA
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(46),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: _loading ? null : _toggleCreateHint,
                            icon: Icon(
                              _showCreateHint
                                  ? Icons.keyboard_arrow_up
                                  : Icons.person_add_outlined,
                              size: 18,
                            ),
                            label: const Text('Create sender account'),
                          ),
                        ),

                        // Inline create account hint panel
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          child: !_showCreateHint
                              ? const SizedBox.shrink()
                              : Container(
                                  key: const ValueKey('createHintPanel'),
                                  margin: const EdgeInsets.only(top: 12),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerHighest
                                        .withValues(alpha: 0.35),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: cs.outlineVariant.withValues(
                                        alpha: 0.60,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                              'Only senders can register here.',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                color: cs.onSurface,
                                                fontSize: 13,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Staff and driver accounts are created by the administrator.',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: muted,
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            Row(
                                              children: [
                                                TextButton(
                                                  style: TextButton.styleFrom(
                                                    foregroundColor: muted,
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 4,
                                                        ),
                                                  ),
                                                  onPressed: _loading
                                                      ? null
                                                      : () => setState(
                                                          () =>
                                                              _showCreateHint =
                                                                  false,
                                                        ),
                                                  child: const Text('Cancel'),
                                                ),
                                                const Spacer(),
                                                ElevatedButton.icon(
                                                  icon: const Icon(
                                                    Icons.arrow_forward,
                                                    size: 16,
                                                  ),
                                                  label: const Text('Continue'),
                                                  onPressed: _loading
                                                      ? null
                                                      : _goToRegister,
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
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 32),
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
        _toast('Invalid phone or password ❌');
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
