import 'package:flutter/material.dart';

import '../../data/routes_helpers.dart';
import '../../services/session.dart';
import '../../services/property_service.dart';
import '../common/property_qr_display_screen.dart';
import 'my_properties_screen.dart';

/// Shown after the sender fills in the registration form.
/// Displays a full summary of what they're about to submit and
/// lets them confirm or go back to edit.
class RegisterPropertyConfirmScreen extends StatefulWidget {
  final String receiverName;
  final String receiverPhone;
  final String description;
  final String destination;
  final int itemCount;
  final List<RouteMatch> routeMatches;
  final VoidCallback onEditPressed;

  const RegisterPropertyConfirmScreen({
    super.key,
    required this.receiverName,
    required this.receiverPhone,
    required this.description,
    required this.destination,
    required this.itemCount,
    required this.routeMatches,
    required this.onEditPressed,
  });

  @override
  State<RegisterPropertyConfirmScreen> createState() =>
      _RegisterPropertyConfirmScreenState();
}

class _RegisterPropertyConfirmScreenState
    extends State<RegisterPropertyConfirmScreen> {
  bool _saving = false;

  String get _routeLabel {
    if (widget.routeMatches.isEmpty) return '—';
    if (widget.routeMatches.length == 1) {
      return widget.routeMatches.first.route.name;
    }
    return 'Multiple routes — desk officer will confirm';
  }

  Future<void> _confirm() async {
    if (_saving) return;
    final actorUserId = (Session.currentUserId ?? '').trim();
    if (actorUserId.isEmpty) {
      _toast('Session expired. Please login again.');
      return;
    }

    setState(() => _saving = true);
    try {
      final routeConfirmed = widget.routeMatches.length == 1;
      final routeId =
          routeConfirmed ? widget.routeMatches.first.route.id : '';
      final routeName =
          routeConfirmed ? widget.routeMatches.first.route.name : '';

      final property = await PropertyService.registerProperty(
        receiverName: widget.receiverName,
        receiverPhone: widget.receiverPhone,
        description: widget.description,
        destination: widget.destination,
        itemCount: widget.itemCount,
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

      // Pop back to sender dashboard / my properties
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MyPropertiesScreen()),
        (route) => route.isFirst,
      );
    } catch (e) {
      if (!mounted) return;
      _toast('Failed to register property: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.55);
    final senderName =
        (Session.currentUserFullName ?? '').trim().isEmpty
            ? 'You'
            : Session.currentUserFullName!.trim();

    final itemWord = widget.itemCount == 1 ? 'item' : 'items';

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        elevation: 2,
        title: const Text('Confirm Shipment'),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Confirm button
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                onPressed: _saving ? null : _confirm,
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
                        'Confirm & Submit',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
              const SizedBox(height: 10),
              // Go back button
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                ),
                onPressed: _saving
                    ? null
                    : () {
                        Navigator.pop(context);
                        widget.onEditPressed();
                      },
                child: const Text('Go Back & Edit'),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // ── Summary sentence ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: cs.primary.withValues(alpha: 0.25),
              ),
            ),
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 15,
                  color: cs.onSurface,
                  height: 1.6,
                ),
                children: [
                  TextSpan(
                    text: senderName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: ' is sending '),
                  TextSpan(
                    text: '${widget.itemCount} $itemWord',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: ' of '),
                  TextSpan(
                    text: widget.description.trim(),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: ' to '),
                  TextSpan(
                    text: widget.receiverName.trim(),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: ' in '),
                  TextSpan(
                    text: widget.destination.trim(),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: ' via the '),
                  TextSpan(
                    text: _routeLabel,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                  const TextSpan(text: ' route.'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Detail cards ──────────────────────────────────────────────
          _sectionCard(
            title: 'Receiver',
            icon: Icons.person_outline,
            children: [
              _row('Name', widget.receiverName.trim(), muted),
              _row('Phone', widget.receiverPhone.trim(), muted),
            ],
          ),

          const SizedBox(height: 12),

          _sectionCard(
            title: 'Shipment',
            icon: Icons.inventory_2_outlined,
            children: [
              _row('Description', widget.description.trim(), muted),
              _row(
                'Items',
                '${widget.itemCount} $itemWord',
                muted,
              ),
              _row('Destination', widget.destination.trim(), muted),
              _row('Route', _routeLabel, muted),
            ],
          ),

          const SizedBox(height: 12),

          // ── Warning if route is ambiguous ─────────────────────────────
          if (widget.routeMatches.length > 1)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFF57F17).withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.alt_route,
                    size: 18,
                    color: Color(0xFFF57F17),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Multiple routes serve ${widget.destination.trim()}. '
                      'The desk officer will confirm the correct route when '
                      'you bring your cargo to the desk.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF8D4A00),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 12),

          // ── What happens next ─────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.40),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What happens next',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                _nextStep(
                  '1',
                  'A property code and QR will be generated.',
                  cs,
                ),
                _nextStep(
                  '2',
                  'Bring your cargo to the desk to pay and have it loaded.',
                  cs,
                ),
                _nextStep(
                  '3',
                  'You will receive SMS updates as your cargo moves.',
                  cs,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, Color muted) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: muted),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _nextStep(String number, String text, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: cs.primary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.75),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}