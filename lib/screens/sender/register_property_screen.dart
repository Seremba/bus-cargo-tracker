import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/property_service.dart';
import '../../services/session.dart';

import '../../data/routes_helpers.dart';
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

  bool _saving = false;
  AutovalidateMode _autoValidate = AutovalidateMode.disabled;

  List<RouteMatch> get _routeMatches =>
      findRoutesByDestination(destinationController.text);

  RouteMatch? get _singleMatch =>
      _routeMatches.length == 1 ? _routeMatches.first : null;

  @override
  void initState() {
    super.initState();
    destinationController.addListener(_onDestinationChanged);
  }

  void _onDestinationChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    destinationController.removeListener(_onDestinationChanged);
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

    final matches = _routeMatches;
    if (matches.isEmpty) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No valid transport route found for this destination.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final count = int.parse(itemCountController.text.trim());

      final bool routeConfirmed = matches.length == 1;
      final String routeId = routeConfirmed ? matches.first.route.id : '';
      final String routeName = routeConfirmed ? matches.first.route.name : '';

      final property = await PropertyService.registerProperty(
        receiverName: receiverNameController.text,
        receiverPhone: receiverPhoneController.text,
        description: descriptionController.text,
        destination: destinationController.text,
        itemCount: count,
        createdByUserId: actorUserId,
        routeId: routeId,
        routeName: routeName,
        routeConfirmed: routeConfirmed,
      );

      if (!mounted) return;

      final propertyCode = property.propertyCode;

      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => PropertyQrDisplayScreen(propertyCode: propertyCode),
        ),
      );

      if (!mounted) return;

      _resetForm();

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MyPropertiesScreen()),
      );
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
    final matches = _routeMatches;
    final singleMatch = _singleMatch;

    String routeMessage;
    if (matches.isEmpty) {
      routeMessage = 'No matching operational route found yet';
    } else if (matches.length == 1) {
      routeMessage = singleMatch!.route.name;
    } else {
      routeMessage =
          'Multiple operational routes match this destination. Desk officer will confirm the route.';
    }

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
              Autocomplete<String>(
                optionsBuilder: (TextEditingValue textEditingValue) {
                  return searchCheckpointNames(
                    textEditingValue.text,
                    limit: 10,
                  );
                },
                onSelected: (value) {
                  destinationController.text = value;
                  setState(() {});
                },
                fieldViewBuilder: (
                  context,
                  textEditingController,
                  focusNode,
                  onFieldSubmitted,
                ) {
                  if (textEditingController.text !=
                      destinationController.text) {
                    textEditingController.value = TextEditingValue(
                      text: destinationController.text,
                      selection: TextSelection.collapsed(
                        offset: destinationController.text.length,
                      ),
                    );
                  }

                  return TextFormField(
                    controller: textEditingController,
                    focusNode: focusNode,
                    textInputAction: TextInputAction.done,
                    decoration: _dec(
                      label: 'Destination',
                      icon: Icons.location_on_outlined,
                      hint: 'Start typing destination...',
                    ),
                    onChanged: (v) {
                      destinationController.text = v;
                      setState(() {});
                    },
                    validator: (value) {
                      final v = value?.trim() ?? '';
                      if (v.isEmpty) return 'Destination required';

                      if (findRoutesByDestination(v).isEmpty) {
                        return 'No transport route configured for this destination';
                      }

                      return null;
                    },
                  );
                },
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.route),
                  title: const Text('Route Resolution'),
                  subtitle: Text(routeMessage),
                ),
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