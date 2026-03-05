import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/property.dart';
import '../../models/property_status.dart';
import '../../services/hive_service.dart';
import '../../services/session.dart';

import '../../data/routes.dart';
import '../common/property_qr_display_screen.dart';
import '../sender/my_properties_screen.dart';

class RegisterPropertyScreen extends StatefulWidget {
  const RegisterPropertyScreen({super.key});

  @override
  State<RegisterPropertyScreen> createState() => _RegisterPropertyScreenState();
}

class _RegisterPropertyScreenState extends State<RegisterPropertyScreen> {
  final _formKey = GlobalKey<FormState>();

  final receiverNameController = TextEditingController();
  final receiverPhoneController = TextEditingController();
  final descriptionController = TextEditingController();
  final destinationController = TextEditingController();
  final itemCountController = TextEditingController(text: '1');

  AppRoute? _selectedRoute;

  bool _saving = false;
  AutovalidateMode _autoValidate = AutovalidateMode.disabled;

  @override
  void dispose() {
    receiverNameController.dispose();
    receiverPhoneController.dispose();
    descriptionController.dispose();
    destinationController.dispose();
    itemCountController.dispose();
    super.dispose();
  }

  // Stable, human-friendly property code.
  // Example: P-20260305-G6KO
  String _generatePropertyCode() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');

    final ms = now.millisecondsSinceEpoch;
    final suffix = (ms % 1679616)
        .toRadixString(36)
        .toUpperCase()
        .padLeft(4, '0');

    return 'P-$y$m$d-$suffix';
  }

  void _resetForm() {
    receiverNameController.clear();
    receiverPhoneController.clear();
    descriptionController.clear();
    destinationController.clear();
    itemCountController.text = '1';
    setState(() => _selectedRoute = null);
  }

  InputDecoration _dec({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
      prefixIcon: Icon(icon),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
      ),
    );
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _autoValidate = AutovalidateMode.onUserInteraction);

    if (!_formKey.currentState!.validate()) return;
    if (_saving) return;

    if (Session.currentUserId == null ||
        (Session.currentUserId ?? '').trim().isEmpty) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session expired. Please login again.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final box = HiveService.propertyBox();
      final count = int.parse(itemCountController.text.trim());
      final route = _selectedRoute!;
      final propertyCode = _generatePropertyCode();

      final property = Property(
        receiverName: receiverNameController.text.trim(),
        receiverPhone: receiverPhoneController.text.trim(),
        description: descriptionController.text.trim(),
        destination: destinationController.text.trim(),
        itemCount: count,
        routeId: route.id,
        routeName: route.name,
        createdAt: DateTime.now(),
        status: PropertyStatus.pending,
        createdByUserId: Session.currentUserId!,
        propertyCode: propertyCode,
        amountPaidTotal: 0,
        currency: 'UGX',
        lastPaidAt: null,
        lastPaymentMethod: '',
        lastPaidByUserId: '',
        lastPaidAtStation: '',
        lastTxnRef: '',
      );

      await box.add(property);
      if (!mounted) return;

      // ✅ CRITICAL: clear any lingering SnackBars before navigation
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      // ✅ UX: QR screen becomes the "success screen"
      final goToMyProperties = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => PropertyQrDisplayScreen(propertyCode: propertyCode),
        ),
      );

      if (!mounted) return;

      // Reset after the success flow
      _resetForm();

      // ✅ If user pressed Done on QR screen => go to My Properties
      if (goToMyProperties == true) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).hideCurrentSnackBar();

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MyPropertiesScreen()),
        );
      } else {
        // If they backed out unexpectedly, still go to My Properties (safe default)
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MyPropertiesScreen()),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        elevation: 2,
        title: const Text('Register Property'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          autovalidateMode: _autoValidate,
          child: ListView(
            children: [
              _section('Receiver'),
              TextFormField(
                controller: receiverNameController,
                textInputAction: TextInputAction.next,
                decoration: _dec(label: 'Receiver Name', icon: Icons.person),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Receiver name required'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: receiverPhoneController,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(15),
                ],
                decoration: _dec(
                  label: 'Receiver Phone',
                  icon: Icons.phone,
                  hint: 'e.g. 0700000000',
                ),
                validator: (value) {
                  final v = value?.trim() ?? '';
                  if (v.isEmpty) return 'Phone required';
                  if (v.length < 9) return 'Enter a valid phone';
                  return null;
                },
              ),
              const SizedBox(height: 18),
              _section('Cargo'),
              TextFormField(
                controller: descriptionController,
                textInputAction: TextInputAction.next,
                decoration: _dec(
                  label: 'Item Description',
                  icon: Icons.inventory_2_outlined,
                  hint: 'e.g. Suitcase, TV, Box',
                ),
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<AppRoute>(
                value: _selectedRoute,
                isExpanded: true,
                decoration: _dec(label: 'Route', icon: Icons.alt_route)
                    .copyWith(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                    ),
                hint: const Text('Select route'),
                items: routes
                    .map(
                      (r) => DropdownMenuItem<AppRoute>(
                        value: r,
                        child: Text(
                          r.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                selectedItemBuilder: (context) {
                  return routes.map((r) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        r.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    );
                  }).toList();
                },
                validator: (v) => v == null ? 'Please select a route' : null,
                onChanged: (v) => setState(() => _selectedRoute = v),
              ),

              const SizedBox(height: 12),
              TextFormField(
                controller: itemCountController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                decoration: _dec(
                  label: 'Number of Items',
                  icon: Icons.format_list_numbered,
                ),
                validator: (value) {
                  final t = value?.trim() ?? '';
                  if (t.isEmpty) return 'Number of items required';
                  final n = int.tryParse(t);
                  if (n == null) return 'Enter a valid number';
                  if (n < 1) return 'Must be at least 1';
                  if (n > 999) return 'Too many items';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: destinationController,
                textInputAction: TextInputAction.done,
                decoration: _dec(
                  label: 'Destination',
                  icon: Icons.place_outlined,
                  hint: 'e.g. Nairobi',
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Destination required'
                    : null,
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: _saving ? null : _submit,
                icon: const Icon(Icons.check_circle_outline),
                label: Text(_saving ? 'Saving...' : 'Submit'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}