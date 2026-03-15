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

  // Item count is managed as an int directly — no text controller needed
  int _itemCount = 1;

  bool _saving = false;
  AutovalidateMode _autoValidate = AutovalidateMode.disabled;

  // Only compute route matches when destination is non-empty
  List<RouteMatch> get _routeMatches {
    final dest = destinationController.text.trim();
    if (dest.isEmpty) return [];
    return findRoutesByDestination(dest);
  }

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
    super.dispose();
  }

  void _resetForm() {
    receiverNameController.clear();
    receiverPhoneController.clear();
    descriptionController.clear();
    destinationController.clear();
    setState(() => _itemCount = 1);
  }

  void _incrementCount() {
    if (_itemCount < 999) setState(() => _itemCount++);
  }

  void _decrementCount() {
    if (_itemCount > 1) setState(() => _itemCount--);
  }

  InputDecoration _dec({
    required String label,
    required IconData icon,
    String? hint,
    String? helper,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      border: const OutlineInputBorder(),
      prefixIcon: Icon(icon),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget _sectionDivider() {
    return const Divider(height: 28, thickness: 1);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _autoValidate = AutovalidateMode.onUserInteraction);

    if (!_formKey.currentState!.validate()) return;
    if (_saving) return;

    final actorUserId = (Session.currentUserId ?? '').trim();
    if (actorUserId.isEmpty) {
      _showSnack('Session expired. Please login again.');
      return;
    }

    final matches = _routeMatches;
    if (matches.isEmpty) {
      _showSnack('No valid transport route found for this destination.');
      return;
    }

    setState(() => _saving = true);

    try {
      final bool routeConfirmed = matches.length == 1;
      final String routeId = routeConfirmed ? matches.first.route.id : '';
      final String routeName = routeConfirmed ? matches.first.route.name : '';

      final property = await PropertyService.registerProperty(
        receiverName: receiverNameController.text,
        receiverPhone: receiverPhoneController.text,
        description: descriptionController.text,
        destination: destinationController.text,
        itemCount: _itemCount,
        createdByUserId: actorUserId,
        routeId: routeId,
        routeName: routeName,
        routeConfirmed: routeConfirmed,
      );

      if (!mounted) return;

      await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              PropertyQrDisplayScreen(propertyCode: property.propertyCode),
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
      _showSnack('Enter a valid number of items.');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to register property: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final matches = _routeMatches;
    final destTyped = destinationController.text.trim().isNotEmpty;

    // Route resolution card state
    final bool routeFound = matches.isNotEmpty;
    final bool routeAmbiguous = matches.length > 1;
    final String routeMessage = !destTyped
        ? ''
        : matches.isEmpty
            ? 'No matching operational route found'
            : matches.length == 1
                ? matches.first.route.name
                : 'Multiple routes match — desk officer will confirm';

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        elevation: 2,
        title: const Text('Register Property'),
      ),
      // ── Pinned Submit button at the bottom ──────────────────────────────
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Submit',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Form(
          key: _formKey,
          autovalidateMode: _autoValidate,
          child: ListView(
            children: [
              const SizedBox(height: 8),

              // ── Receiver section ────────────────────────────────────────
              _sectionHeader('Receiver'),
              TextFormField(
                controller: receiverNameController,
                textInputAction: TextInputAction.next,
                decoration: _dec(
                  label: 'Receiver Name',
                  icon: Icons.person_outline,
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
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
                  icon: Icons.phone_outlined,
                  hint: 'e.g. 0700000000',
                ),
                validator: (v) {
                  final s = v?.trim() ?? '';
                  if (s.isEmpty) return 'Phone required';
                  if (s.length < 9) return 'Enter a valid phone number';
                  return null;
                },
              ),

              _sectionDivider(),

              // ── Property section ────────────────────────────────────────
              _sectionHeader('Property'),
              TextFormField(
                controller: descriptionController,
                textInputAction: TextInputAction.next,
                decoration: _dec(
                  label: 'Item Description',
                  icon: Icons.inventory_2_outlined,
                  hint: 'e.g. Electronics, Clothes, Documents',
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Description required'
                    : null,
              ),
              const SizedBox(height: 14),

              // ── Item count stepper ──────────────────────────────────────
              Row(
                children: [
                  const Icon(
                    Icons.format_list_numbered,
                    size: 22,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Number of Items',
                    style: TextStyle(fontSize: 15),
                  ),
                  const Spacer(),
                  // Decrement
                  _stepperButton(
                    icon: Icons.remove,
                    onTap: _decrementCount,
                    enabled: _itemCount > 1,
                    cs: cs,
                  ),
                  const SizedBox(width: 12),
                  // Count display
                  SizedBox(
                    width: 36,
                    child: Text(
                      '$_itemCount',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Increment
                  _stepperButton(
                    icon: Icons.add,
                    onTap: _incrementCount,
                    enabled: _itemCount < 999,
                    cs: cs,
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // ── Destination with autocomplete ───────────────────────────
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
                      hint: 'e.g. Bumala, Juba, Nairobi',
                      helper: 'Type the destination town or station name',
                    ),
                    onChanged: (v) {
                      destinationController.text = v;
                      setState(() {});
                    },
                    validator: (v) {
                      final s = v?.trim() ?? '';
                      if (s.isEmpty) return 'Destination required';
                      if (findRoutesByDestination(s).isEmpty) {
                        return 'No transport route configured for this destination';
                      }
                      return null;
                    },
                  );
                },
              ),

              // ── Route resolution card — only shown after typing ─────────
              if (destTyped) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: !routeFound
                        ? cs.errorContainer.withValues(alpha: 0.45)
                        : routeAmbiguous
                            ? const Color(0xFFFFF8E1)
                            : cs.primaryContainer.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: !routeFound
                          ? cs.error.withValues(alpha: 0.35)
                          : routeAmbiguous
                              ? const Color(0xFFF57F17).withValues(alpha: 0.35)
                              : cs.primary.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        !routeFound
                            ? Icons.error_outline
                            : routeAmbiguous
                                ? Icons.alt_route
                                : Icons.check_circle_outline,
                        size: 20,
                        color: !routeFound
                            ? cs.error
                            : routeAmbiguous
                                ? const Color(0xFFF57F17)
                                : cs.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              !routeFound
                                  ? 'No route found'
                                  : routeAmbiguous
                                      ? 'Multiple routes matched'
                                      : 'Route confirmed',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: !routeFound
                                    ? cs.error
                                    : routeAmbiguous
                                        ? const Color(0xFFF57F17)
                                        : cs.primary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              routeMessage,
                              style: TextStyle(
                                fontSize: 12,
                                color: !routeFound
                                    ? cs.onErrorContainer
                                    : cs.onSurface.withValues(alpha: 0.75),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Bottom padding so last field clears the pinned button
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _stepperButton({
    required IconData icon,
    required VoidCallback onTap,
    required bool enabled,
    required ColorScheme cs,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: enabled
              ? cs.primary.withValues(alpha: 0.10)
              : cs.onSurface.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: enabled
                ? cs.primary.withValues(alpha: 0.35)
                : cs.onSurface.withValues(alpha: 0.15),
          ),
        ),
        child: Icon(
          icon,
          size: 18,
          color: enabled ? cs.primary : cs.onSurface.withValues(alpha: 0.30),
        ),
      ),
    );
  }
}