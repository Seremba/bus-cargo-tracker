import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/property_service.dart';
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

    final actorUserId = (Session.currentUserId ?? '').trim();
    if (actorUserId.isEmpty) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session expired. Please login again.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final count = int.parse(itemCountController.text.trim());
      final route = _selectedRoute!;

      final property = await PropertyService.registerProperty(
        receiverName: receiverNameController.text,
        receiverPhone: receiverPhoneController.text,
        description: descriptionController.text,
        destination: destinationController.text,
        itemCount: count,
        createdByUserId: actorUserId,
        routeId: route.id,
        routeName: route.name,
      );

      if (!mounted) return;

      final propertyCode = property.propertyCode;

      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      final goToMyProperties = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => PropertyQrDisplayScreen(propertyCode: propertyCode),
        ),
      );

      if (!mounted) return;

      _resetForm();

      if (goToMyProperties == true) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).hideCurrentSnackBar();

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MyPropertiesScreen()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MyPropertiesScreen()),
        );
      }
    } on FormatException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid number of items.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to register property: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
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
              const SizedBox(height: 16),
              _section('Property'),
              TextFormField(
                controller: descriptionController,
                textInputAction: TextInputAction.next,
                decoration: _dec(
                  label: 'Item Description',
                  icon: Icons.inventory_2_outlined,
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Description required'
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<AppRoute>(
                initialValue: _selectedRoute,
                decoration: _dec(label: 'Route', icon: Icons.route),
                hint: const Text('Select route'),
                items: routes
                    .map((r) => DropdownMenuItem(value: r, child: Text(r.name)))
                    .toList(),
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
                  icon: Icons.location_on_outlined,
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
}
