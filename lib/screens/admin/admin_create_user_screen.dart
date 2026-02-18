import 'package:flutter/material.dart';

import '../../models/user_role.dart';
import '../../services/auth_service.dart';
import '../../services/role_guard.dart';

class AdminCreateUserScreen extends StatefulWidget {
  const AdminCreateUserScreen({super.key});

  @override
  State<AdminCreateUserScreen> createState() => _AdminCreateUserScreenState();
}

class _AdminCreateUserScreenState extends State<AdminCreateUserScreen> {
  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _station = TextEditingController();

  bool _loading = false;
  UserRole _role = UserRole.staff;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _password.dispose();
    _station.dispose();
    super.dispose();
  }

  bool get _stationEnabled =>
      _role == UserRole.staff || _role == UserRole.deskCargoOfficer;

  bool get _stationRequired => _role == UserRole.staff;

  Widget _notAuthorized() =>
      const Scaffold(body: Center(child: Text('Not authorized')));

  @override
  Widget build(BuildContext context) {
    if (!RoleGuard.hasRole(UserRole.admin)) return _notAuthorized();

    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Create User')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              const Text(
                'Create a new user account',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return 'Name required';
                  if (t.length < 2) return 'Name too short';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return 'Phone required';
                  if (t.length < 9) return 'Enter a valid phone';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Temporary Password',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return 'Password required';
                  if (t.length < 4) return 'At least 4 characters';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<UserRole>(
                initialValue: _role,
                decoration: const InputDecoration(
                  labelText: 'Role',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: UserRole.staff,
                    child: Text('Staff (Station required)'),
                  ),
                  DropdownMenuItem(
                    value: UserRole.driver,
                    child: Text('Driver'),
                  ),
                  DropdownMenuItem(
                    value: UserRole.deskCargoOfficer,
                    child: Text('Desk Cargo Officer'),
                  ),
                ],

                onChanged: (v) {
                  setState(() {
                    _role = v ?? UserRole.staff;
                    if (!_stationEnabled) _station.clear();
                  });
                },
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _station,
                enabled: _stationEnabled,
                decoration: InputDecoration(
                  labelText: _stationRequired
                      ? 'Station Name (required)'
                      : (_stationEnabled
                            ? 'Station Name (optional)'
                            : 'Station Name (not applicable)'),
                  border: const OutlineInputBorder(),
                ),
                validator: (v) {
                  if (!_stationRequired) return null;
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return 'Station required for staff';
                  return null;
                },
              ),

              const SizedBox(height: 18),

              ElevatedButton.icon(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.person_add),
                label: Text(_loading ? 'Creating...' : 'Create user'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final user = await AuthService.register(
        fullName: _name.text,
        phone: _phone.text,
        password: _password.text,
        role: _role,
        stationName: _stationEnabled && _station.text.trim().isNotEmpty
            ? _station.text.trim()
            : null,
      );

      if (!mounted) return;

      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed ❌ Phone already exists (or not allowed)'),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('User created ✅ ${user.fullName} (${user.role.name})'),
        ),
      );

      //  Route back after success
      Navigator.of(context).pop(user);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
