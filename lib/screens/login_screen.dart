import 'package:flutter/material.dart';

import '../models/user_role.dart';
import '../services/auth_service.dart';
import '../services/hive_service.dart';
import '../services/session.dart';

import 'forgot_password_screen.dart';
import 'register_screen.dart';

import 'sender/sender_dashboard.dart';
import 'dashboards/staff_dashboard.dart';
import 'dashboards/driver_dashboard.dart';
import 'dashboards/admin_dashboard.dart';
import 'dashboards/desk_cargo_officer_dashboard.dart'; // ✅ add this

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        elevation: 2,
        backgroundColor: Colors.blue,
        title: const Text('Login'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone Number',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final v = value?.trim() ?? '';
                      if (v.isEmpty) return 'Phone number is required';
                      if (v.length < 9) return 'Enter a valid phone number';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
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
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ForgotPasswordScreen(),
                            ),
                          );
                        },
                        child: const Text('Forgot password?'),
                      ),
                      TextButton(
                        onPressed: () {
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
                    child: Text(_loading ? 'Logging in...' : 'Login'),
                  ),
                ],
              ),
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
      await HiveService.openAllBoxes();

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

      HiveService.setUser(user.id);
      Session.currentUserId = user.id;
      Session.currentRole = user.role;
      Session.currentStationName = user.stationName;

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

  @override
  void dispose() {
    phoneController.dispose();
    passwordController.dispose();
    super.dispose();
  }
}
