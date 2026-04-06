import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/routes.dart';
import '../../models/user_role.dart';
import '../../services/auth_service.dart';
import '../../services/role_guard.dart';

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
  _Country(name: 'Uganda', flag: '🇺🇬', dialCode: '+256', placeholder: '7XXXXXXXX'),
  _Country(name: 'Kenya', flag: '🇰🇪', dialCode: '+254', placeholder: '7XXXXXXXX'),
  _Country(name: 'South Sudan', flag: '🇸🇸', dialCode: '+211', placeholder: '9XXXXXXXX'),
  _Country(name: 'Rwanda', flag: '🇷🇼', dialCode: '+250', placeholder: '7XXXXXXXX'),
  _Country(name: 'DR Congo', flag: '🇨🇩', dialCode: '+243', placeholder: '8XXXXXXXX'),
];

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
  bool _hidePass = true;
  UserRole _role = UserRole.staff;
  AppRoute? _selectedRoute;
  _Country _selectedCountry = _countries.first;

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

  String _digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  String _buildE164() {
    final digits = _digitsOnly(_phone.text.trim());
    if (digits.isEmpty) return '';
    final cleaned = digits.startsWith('0') ? digits.substring(1) : digits;
    return '${_selectedCountry.dialCode}$cleaned';
  }

  bool _isValidPhone() {
    final e164 = _buildE164();
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
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
                  fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.30),
                ),
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return 'Name required';
                  if (t.length < 2) return 'Name too short';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // ── Phone with country code picker ──────────────────────────
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
                        color: cs.surfaceContainerHighest.withValues(alpha: 0.30),
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
                        helperText: 'Without leading 0 or country code',
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor:
                            cs.surfaceContainerHighest.withValues(alpha: 0.30),
                      ),
                      validator: (v) {
                        if ((v ?? '').trim().isEmpty) return 'Phone required';
                        if (!_isValidPhone()) return 'Enter a valid phone number';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Temporary Password
              TextFormField(
                controller: _password,
                obscureText: _hidePass,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Temporary Password',
                  helperText: 'Share this with the user — they can change it later.',
                  helperMaxLines: 2,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_outline),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.30),
                  suffixIcon: IconButton(
                    tooltip: _hidePass ? 'Show password' : 'Hide password',
                    icon: Icon(
                      _hidePass
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () => setState(() => _hidePass = !_hidePass),
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
                  fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.30),
                ),
                items: const [
                  DropdownMenuItem(
                    value: UserRole.staff,
                    child: Text('Staff', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  DropdownMenuItem(
                    value: UserRole.driver,
                    child: Text('Driver', maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  DropdownMenuItem(
                    value: UserRole.deskCargoOfficer,
                    child: Text('Desk Cargo Officer', maxLines: 1, overflow: TextOverflow.ellipsis),
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
                      Icon(Icons.info_outline, size: 14, color: cs.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _roleHelperText,
                          style: TextStyle(fontSize: 12, color: cs.primary),
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
                    fillColor:
                        cs.surfaceContainerHighest.withValues(alpha: 0.30),
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
                    fillColor:
                        cs.surfaceContainerHighest.withValues(alpha: 0.30),
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
                    return v == null ? 'Route is required for drivers' : null;
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

    setState(() => _loading = true);
    try {
      // Build full E.164 phone number with selected country code
      final fullPhone = _buildE164();

      final user = await AuthService.adminCreateUser(
        fullName: _name.text.trim(),
        phone: fullPhone,
        password: _password.text.trim(),
        role: _role,
        stationName: _stationEnabled && _station.text.trim().isNotEmpty
            ? _station.text.trim()
            : null,
        assignedRouteId: _role == UserRole.driver ? _selectedRoute?.id : null,
        assignedRouteName:
            _role == UserRole.driver ? _selectedRoute?.name : null,
      );

      if (!mounted) return;

      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed ❌ Phone already exists or not allowed.'),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('User created ✅ ${user.fullName} (${user.role.name})'),
        ),
      );

      Navigator.of(context).pop(user);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}