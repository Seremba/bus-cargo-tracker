import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/property.dart';
import '../../models/property_status.dart';
import '../../services/hive_service.dart';
import '../../services/session.dart';
import '../sender/my_properties_screen.dart';
import '../../data/routes.dart';
import '../common/property_qr_display_screen.dart';

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
  // Example: P-20260213-8F3K
  String _generatePropertyCode() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');

    // 4-char base36 suffix (from milliseconds) — no extra packages.
    final ms = now.millisecondsSinceEpoch;
    final suffix = (ms % 1679616)
        .toRadixString(36)
        .toUpperCase()
        .padLeft(4, '0');

    return 'P-$y$m$d-$suffix';
  }

  Future<void> _showPropertyCodeDialog(String code) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Property Registered ✅'),
        content: Text(
          'Property Code:\n\n$code\n\n'
          'This code is used for the Property QR (payment + lookup).',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Property code copied ✅')),
              );
            },
            child: const Text('Copy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
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
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          autovalidateMode: _autoValidate,
          child: ListView(
            children: [
              TextFormField(
                controller: receiverNameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Receiver Name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Receiver name required'
                    : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: receiverPhoneController,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(15),
                ],
                decoration: const InputDecoration(
                  labelText: 'Receiver Phone',
                  border: OutlineInputBorder(),
                  hintText: 'e.g. 0700000000',
                ),
                validator: (value) {
                  final v = value?.trim() ?? '';
                  if (v.isEmpty) return 'Phone required';
                  if (v.length < 9) return 'Enter a valid phone';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: descriptionController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Item Description',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<AppRoute>(
                initialValue: _selectedRoute,
                decoration: const InputDecoration(
                  labelText: 'Route',
                  border: OutlineInputBorder(),
                ),
                hint: const Text('Select route'),
                items: routes
                    .map((r) => DropdownMenuItem(value: r, child: Text(r.name)))
                    .toList(),
                validator: (v) => v == null ? 'Please select a route' : null,
                onChanged: (v) => setState(() => _selectedRoute = v),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: itemCountController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                decoration: const InputDecoration(
                  labelText: 'Number of Items',
                  border: OutlineInputBorder(),
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
              const SizedBox(height: 16),

              TextFormField(
                controller: destinationController,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Destination',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Destination required'
                    : null,
              ),
              const SizedBox(height: 24),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _saving ? null : _submit,
                child: Text(_saving ? 'Saving...' : 'Submit'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _autoValidate = AutovalidateMode.onUserInteraction);

    if (!_formKey.currentState!.validate()) return;
    if (_saving) return;

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

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PropertyQrDisplayScreen(propertyCode: propertyCode),
        ),
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MyPropertiesScreen()),
      );

      receiverNameController.clear();
      receiverPhoneController.clear();
      descriptionController.clear();
      destinationController.clear();
      itemCountController.text = '1';
      setState(() => _selectedRoute = null);

      if (!mounted) return;

      await _showPropertyCodeDialog(propertyCode);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MyPropertiesScreen()),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
