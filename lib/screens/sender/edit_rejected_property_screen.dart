import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/routes.dart';
import '../../models/property.dart';
import '../../models/property_status.dart';
import '../../services/audit_service.dart';
import '../../services/hive_service.dart';
import '../../services/property_service.dart';
import '../../services/session.dart';
import '../../services/sync_service.dart';

class EditRejectedPropertyScreen extends StatefulWidget {
  final Property property;
  const EditRejectedPropertyScreen({super.key, required this.property});

  @override
  State<EditRejectedPropertyScreen> createState() =>
      _EditRejectedPropertyScreenState();
}

class _EditRejectedPropertyScreenState
    extends State<EditRejectedPropertyScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _receiverName;
  late final TextEditingController _receiverPhone;
  late final TextEditingController _description;
  late final TextEditingController _destination;
  late final TextEditingController _itemCount;

  String _routeId = '';
  String _routeName = '';

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.property;
    _receiverName = TextEditingController(text: p.receiverName.trim());
    _receiverPhone = TextEditingController(text: p.receiverPhone.trim());
    _description = TextEditingController(text: p.description.trim());
    _destination = TextEditingController(text: p.destination.trim());
    _itemCount = TextEditingController(text: p.itemCount.toString());
    _routeId = p.routeId.trim();
    _routeName = p.routeName.trim();
  }

  @override
  void dispose() {
    _receiverName.dispose();
    _receiverPhone.dispose();
    _description.dispose();
    _destination.dispose();
    _itemCount.dispose();
    super.dispose();
  }

  bool get _hasChanges {
    final p = widget.property;
    return _receiverName.text.trim() != p.receiverName.trim() ||
        _receiverPhone.text.trim() != p.receiverPhone.trim() ||
        _description.text.trim() != p.description.trim() ||
        _destination.text.trim() != p.destination.trim() ||
        int.tryParse(_itemCount.text.trim()) != p.itemCount ||
        _routeId != p.routeId.trim() ||
        _routeName != p.routeName.trim();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_hasChanges) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No changes to save.')));
      return;
    }

    setState(() => _saving = true);

    try {
      final box = HiveService.propertyBox();
      final fresh = box.get(widget.property.key) ?? widget.property;

      // Only editable when rejected — once submitted for review (underReview)
      // the sender must wait for admin to approve or deny before editing again.
      if (fresh.status != PropertyStatus.rejected) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                fresh.status == PropertyStatus.underReview
                    ? 'Already submitted for review — wait for admin decision ⏳'
                    : 'Property can no longer be edited ❌',
              ),
            ),
          );
        }
        return;
      }

      final oldValues = {
        'receiverName': fresh.receiverName,
        'receiverPhone': fresh.receiverPhone,
        'description': fresh.description,
        'destination': fresh.destination,
        'itemCount': fresh.itemCount,
        'routeId': fresh.routeId,
        'routeName': fresh.routeName,
      };

      // Core registration fields are final on Property — we create a
      // replacement object copying all mutable state across, then overwrite
      // the box entry at the same key.
      final updated = Property(
        receiverName: _receiverName.text.trim(),
        receiverPhone: _receiverPhone.text.trim(),
        description: _description.text.trim(),
        destination: _destination.text.trim(),
        itemCount: int.parse(_itemCount.text.trim()),
        routeId: _routeId,
        routeName: _routeName,
        // Carry over everything else unchanged
        createdAt: fresh.createdAt,
        status: fresh.status,
        createdByUserId: fresh.createdByUserId,
        propertyCode: fresh.propertyCode,
        amountPaidTotal: fresh.amountPaidTotal,
        currency: fresh.currency,
        lastPaidAt: fresh.lastPaidAt,
        lastPaymentMethod: fresh.lastPaymentMethod,
        lastPaidByUserId: fresh.lastPaidByUserId,
        lastPaidAtStation: fresh.lastPaidAtStation,
        lastTxnRef: fresh.lastTxnRef,
        aggregateVersion: fresh.aggregateVersion + 1,
        routeConfirmed: fresh.routeConfirmed,
        // S2: clear commit hash so desk recomputes on next load
        isLocked: false,
        commitHash: null,
      );

      // Copy mutable fields that are not constructor params
      updated.loadedAt = fresh.loadedAt;
      updated.loadedAtStation = fresh.loadedAtStation;
      updated.loadedByUserId = fresh.loadedByUserId;
      updated.inTransitAt = fresh.inTransitAt;
      updated.deliveredAt = fresh.deliveredAt;
      updated.pickedUpAt = fresh.pickedUpAt;
      updated.tripId = fresh.tripId;
      updated.rejectionCategory = fresh.rejectionCategory;
      updated.rejectionReason = fresh.rejectionReason;
      updated.rejectedByUserId = fresh.rejectedByUserId;
      updated.rejectedAt = fresh.rejectedAt;
      updated.notifyReceiver = fresh.notifyReceiver;
      updated.trackingCode = fresh.trackingCode;
      updated.receiverNotifyChannel = fresh.receiverNotifyChannel;

      await HiveService.propertyBox().put(fresh.key, updated);
      final saved2 = HiveService.propertyBox().get(fresh.key) ?? updated;

      final newValues = {
        'receiverName': saved2.receiverName,
        'receiverPhone': saved2.receiverPhone,
        'description': saved2.description,
        'destination': saved2.destination,
        'itemCount': saved2.itemCount,
        'routeId': saved2.routeId,
        'routeName': saved2.routeName,
      };

      // Build a human-readable diff for the audit log
      final diffLines = <String>[];
      oldValues.forEach((k, v) {
        final nv = newValues[k];
        if (v.toString() != nv.toString()) {
          diffLines.add('$k: "$v" → "$nv"');
        }
      });

      await AuditService.log(
        action: 'PROPERTY_EDITED_AFTER_REJECTION',
        propertyKey: saved2.key.toString(),
        details:
            'Sender ${(Session.currentUserId ?? '').trim()} edited rejected property '
            '${saved2.propertyCode}.\nChanges: ${diffLines.join('; ')}',
      );

      await SyncService.enqueueAdminOverrideApplied(
        aggregateType: 'property',
        aggregateId: saved2.propertyCode.trim(),
        actorUserId: (Session.currentUserId ?? '').trim(),
        payload: {
          'propertyCode': saved2.propertyCode,
          'action': 'PROPERTY_EDITED_AFTER_REJECTION',
          'changes': oldValues.keys
              .where((k) => oldValues[k].toString() != newValues[k].toString())
              .map(
                (k) => {'field': k, 'from': oldValues[k], 'to': newValues[k]},
              )
              .toList(),
          'aggregateVersion': saved2.aggregateVersion,
        },
      );

      // Build change summary for admin notification
      final summary = diffLines.join(', ');

      // Automatically submit for re-review now that edits are saved
      await PropertyService.requestReReview(saved2, changeSummary: summary);

      if (mounted) {
        Navigator.pop(
          context,
          true,
        ); // signal that edits + review request were saved
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save: $e ❌')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.55);

    // All available routes from the data layer
    final allRoutes = routes;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        elevation: 2,
        title: const Text('Edit Property'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            // Info banner
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFFF8F00).withValues(alpha: 0.40),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFFFF8F00), size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Edit the details below and tap "Save & Request Review". '
                      'Once submitted, you cannot edit again until admin responds.',
                      style: TextStyle(fontSize: 13, color: Color(0xFFE65100)),
                    ),
                  ),
                ],
              ),
            ),

            _sectionLabel('Receiver details', cs),
            const SizedBox(height: 8),

            TextFormField(
              controller: _receiverName,
              decoration: const InputDecoration(
                labelText: 'Receiver name',
                prefixIcon: Icon(Icons.person_outline),
              ),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Receiver name is required' : null,
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _receiverPhone,
              decoration: const InputDecoration(
                labelText: 'Receiver phone',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
              keyboardType: TextInputType.phone,
              validator: (v) => (v ?? '').trim().isEmpty
                  ? 'Receiver phone is required'
                  : null,
            ),
            const SizedBox(height: 20),

            _sectionLabel('Cargo details', cs),
            const SizedBox(height: 8),

            TextFormField(
              controller: _description,
              decoration: const InputDecoration(
                labelText: 'Description',
                prefixIcon: Icon(Icons.inventory_2_outlined),
              ),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Description is required' : null,
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _itemCount,
              decoration: const InputDecoration(
                labelText: 'Item count',
                prefixIcon: Icon(Icons.numbers_outlined),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) {
                final n = int.tryParse(v ?? '');
                if (n == null || n < 1) return 'Must be at least 1';
                return null;
              },
            ),
            const SizedBox(height: 20),

            _sectionLabel('Route & destination', cs),
            const SizedBox(height: 8),

            TextFormField(
              controller: _destination,
              decoration: const InputDecoration(
                labelText: 'Destination',
                prefixIcon: Icon(Icons.place_outlined),
              ),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Destination is required' : null,
            ),
            const SizedBox(height: 12),

            // Route picker — isExpanded prevents right overflow on device
            DropdownButtonFormField<String>(
              isExpanded: true,
              value: _routeId.isEmpty ? null : _routeId,
              decoration: const InputDecoration(
                labelText: 'Route',
                prefixIcon: Icon(Icons.route_outlined),
              ),
              items: allRoutes
                  .map(
                    (r) => DropdownMenuItem(
                      value: r.id,
                      child: Text(r.name, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                final route = allRoutes.firstWhere((r) => r.id == v);
                setState(() {
                  _routeId = route.id;
                  _routeName = route.name;
                });
              },
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Route is required' : null,
            ),

            if (_routeName.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Selected: $_routeName',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ],

            const SizedBox(height: 32),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: ElevatedButton.icon(
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_circle_outline),
            label: const Text('Save & Request Review'),
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text, ColorScheme cs) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: cs.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
