import 'package:flutter/material.dart';
import 'package:intl_phone_field/intl_phone_field.dart';

import '../../data/routes.dart';
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
  final _password = TextEditingController();
  final _station = TextEditingController();

  bool _loading = false;
  bool _hidePass = true;
  UserRole _role = UserRole.staff;
  AppRoute? _selectedRoute;

  // Full E.164 phone number built by IntlPhoneField
  String _fullPhone = '';

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    _station.dispose();
    super.dispose();
  }

  bool get _stationEnabled =>
      _role == UserRole.staff || _role == UserRole.deskCargoOfficer;

  bool get _stationRequired => _role == UserRole.staff;

  bool get _routeEnabled => _role == UserRole.driver;

  String get _roleHelperText {
    switch (_role) {
      case UserRole.staff:
        return 'Can mark cargo delivered and confirm pickups. Station required.';
      case UserRole.driver:
        return 'Can start trips and track checkpoints. Route assignment required.';
      case UserRole.deskCargoOfficer:
        return 'Can mark cargo as loaded at the station. Station optional.';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!RoleGuard.hasRole(UserRole.admin)) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.55);

    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Create User')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: ElevatedButton.icon(
            onPressed: _loading ? null : _submit,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.person_add_outlined),
            label: Text(
              _loading ? 'Creating...' : 'Create user',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              const SizedBox(height: 12),

              const Text(
                'New user account',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                'Fill in the details below to create a staff, driver, or desk officer account.',
                style: TextStyle(fontSize: 13, color: muted),
              ),

              const SizedBox(height: 20),

              // Full Name
              TextFormField(
                controller: _name,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.person_outline),
                  filled: true,
                  fillColor:
                      cs.surfaceContainerHighest.withValues(alpha: 0.30),
                ),
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return 'Name required';
                  if (t.length < 2) return 'Name too short';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // ── International phone field ──────────────────────────────
              IntlPhoneField(
                enabled: !_loading,
                initialCountryCode: 'UG',
                decoration: InputDecoration(
                  labelText: 'Phone Number',
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor:
                      cs.surfaceContainerHighest.withValues(alpha: 0.30),
                ),
                onChanged: (phone) {
                  _fullPhone = phone.completeNumber;
                },
                onCountryChanged: (_) {
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

              // Temporary Password
              TextFormField(
                controller: _password,
                obscureText: _hidePass,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Temporary Password',
                  helperText:
                      'Share this with the user — they can change it later.',
                  helperMaxLines: 2,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_outline),
                  filled: true,
                  fillColor:
                      cs.surfaceContainerHighest.withValues(alpha: 0.30),
                  suffixIcon: IconButton(
                    tooltip:
                        _hidePass ? 'Show password' : 'Hide password',
                    icon: Icon(
                      _hidePass
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () =>
                        setState(() => _hidePass = !_hidePass),
                  ),
                ),
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return 'Password required';
                  if (t.length < 4) return 'At least 4 characters';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              const Divider(height: 1),
              const SizedBox(height: 16),

              // Role dropdown
              DropdownButtonFormField<UserRole>(
                value: _role,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Role',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.badge_outlined),
                  filled: true,
                  fillColor:
                      cs.surfaceContainerHighest.withValues(alpha: 0.30),
                ),
                items: const [
                  DropdownMenuItem(
                    value: UserRole.staff,
                    child: Text('Staff',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  DropdownMenuItem(
                    value: UserRole.driver,
                    child: Text('Driver',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  DropdownMenuItem(
                    value: UserRole.deskCargoOfficer,
                    child: Text('Desk Cargo Officer',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
                onChanged: (v) {
                  setState(() {
                    _role = v ?? UserRole.staff;
                    if (!_stationEnabled) _station.clear();
                    if (!_routeEnabled) _selectedRoute = null;
                  });
                },
              ),

              // Role helper text
              if (_roleHelperText.isNotEmpty) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          size: 14, color: cs.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _roleHelperText,
                          style: TextStyle(
                              fontSize: 12, color: cs.primary),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // Station field
              if (_stationEnabled) ...[
                TextFormField(
                  controller: _station,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: _stationRequired
                        ? 'Station Name'
                        : 'Station Name (optional)',
                    hintText: 'e.g. Kampala, Juba',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.location_on_outlined),
                    filled: true,
                    fillColor: cs.surfaceContainerHighest
                        .withValues(alpha: 0.30),
                  ),
                  validator: (v) {
                    if (!_stationRequired) return null;
                    final t = v?.trim() ?? '';
                    if (t.isEmpty) return 'Station is required for staff';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
              ],

              // Route dropdown
              if (_routeEnabled) ...[
                DropdownButtonFormField<AppRoute>(
                  value: _selectedRoute,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Assigned Route',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.route_outlined),
                    filled: true,
                    fillColor: cs.surfaceContainerHighest
                        .withValues(alpha: 0.30),
                  ),
                  items: routes
                      .map(
                        (r) => DropdownMenuItem(
                          value: r,
                          child: Text(
                            r.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _selectedRoute = v),
                  validator: (v) {
                    if (_role != UserRole.driver) return null;
                    return v == null
                        ? 'Route is required for drivers'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
              ],

              const SizedBox(height: 8),

              // Info note
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.50),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: muted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Only staff, driver, and desk officer accounts can be created here. '
                        'Sender accounts are self-registered via the app.',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_fullPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid phone number')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final user = await AuthService.adminCreateUser(
        fullName: _name.text.trim(),
        phone: _fullPhone,
        password: _password.text.trim(),
        role: _role,
        stationName: _stationEnabled && _station.text.trim().isNotEmpty
            ? _station.text.trim()
            : null,
        assignedRouteId:
            _role == UserRole.driver ? _selectedRoute?.id : null,
        assignedRouteName:
            _role == UserRole.driver ? _selectedRoute?.name : null,
      );

      if (!mounted) return;

      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Failed ❌ Phone already exists or not allowed.'),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'User created ✅ ${user.fullName} (${user.role.name})'),
        ),
      );

      Navigator.of(context).pop(user);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}