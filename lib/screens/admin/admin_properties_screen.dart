import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/property.dart';
import '../../models/property_status.dart';
import '../../models/user_role.dart';
import '../../services/hive_service.dart';
import '../../services/property_service.dart';
import '../../services/role_guard.dart';

class AdminPropertiesScreen extends StatefulWidget {
  const AdminPropertiesScreen({super.key});

  @override
  State<AdminPropertiesScreen> createState() => _AdminPropertiesScreenState();
}

class _AdminPropertiesScreenState extends State<AdminPropertiesScreen> {
  final Set<dynamic> _repairedKeys = <dynamic>{};

  bool _autoRepairScheduled = false;
  bool _isRepairing = false;

  // Safe helpers (works for String or String?)
  String _s(String? v) => v ?? '';
  String _dashIfEmpty(String? v) {
    final t = (v ?? '').trim();
    return t.isEmpty ? '—' : t;
  }

  String _statusText(PropertyStatus status) {
    switch (status) {
      case PropertyStatus.pending:
        return '🟡 Pending';
      case PropertyStatus.inTransit:
        return '🔵 In Transit';
      case PropertyStatus.delivered:
        return '🟢 Delivered';
      case PropertyStatus.pickedUp:
        return '✅ Picked Up';
    }
  }

  bool _isLegacyBrokenLoaded(Property p) {
    final impliesLoaded = p.status == PropertyStatus.inTransit ||
        p.status == PropertyStatus.delivered ||
        p.status == PropertyStatus.pickedUp;
    return impliesLoaded && p.loadedAt == null;
  }

  @override
  Widget build(BuildContext context) {
    if (!RoleGuard.hasRole(UserRole.admin)) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    final box = HiveService.propertyBox();

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        elevation: 2,
        title: const Text('All Properties'),
        actions: [
          IconButton(
            tooltip: 'Repair legacy loaded milestones',
            icon: _isRepairing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.build_circle_outlined),
            onPressed: _isRepairing ? null : () => _manualRepairAll(box),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: box.listenable(),
        builder: (context, Box<Property> box, _) {
          final items = box.values.toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          if (items.isEmpty) {
            return const Center(child: Text('No properties yet.'));
          }

          // Auto-repair opportunistically (ONCE) outside build
          _scheduleAutoRepairOnce(items);

          final brokenCount = items.where(_isLegacyBrokenLoaded).length;

          return ListView(
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              if (brokenCount > 0)
                Card(
                  margin: const EdgeInsets.all(12),
                  color: Colors.orangeAccent.withValues(alpha: 0.18),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '$brokenCount old record(s) are missing Loaded milestone.\n'
                            'They will be repaired automatically when you open this screen.',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        TextButton.icon(
                          onPressed:
                              _isRepairing ? null : () => _manualRepairAll(box),
                          icon: const Icon(Icons.build, size: 18),
                          label: const Text('Repair now'),
                        ),
                      ],
                    ),
                  ),
                ),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final p = items[index];

                  final routeText = _dashIfEmpty(p.routeName);
                  final senderText = _dashIfEmpty(p.createdByUserId);

                  final bool legacyBroken = _isLegacyBrokenLoaded(p);
                  final bool loadedDone = p.loadedAt != null ||
                      p.status == PropertyStatus.inTransit ||
                      p.status == PropertyStatus.delivered ||
                      p.status == PropertyStatus.pickedUp;

                  return Card(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: ListTile(
                      title: Row(
                        children: [
                          Expanded(child: Text(_s(p.receiverName))),
                          const SizedBox(width: 8),
                          _StatusChip(text: _statusText(p.status)),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${_s(p.destination)} • ${_s(p.receiverPhone)}'),
                            const SizedBox(height: 4),
                            Text(
                              'Items: ${p.itemCount} • Route: $routeText',
                              style: const TextStyle(fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Sender: $senderText',
                              style: const TextStyle(fontSize: 12),
                            ),
                            Text(
                              'Created: ${p.createdAt.toLocal().toString().substring(0, 16)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            const SizedBox(height: 6),

                            // UI: show Loaded milestone clarity
                            Row(
                              children: [
                                Icon(
                                  loadedDone
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  size: 16,
                                  color: loadedDone
                                      ? Colors.green
                                      : Colors.black54,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Loaded: ${p.loadedAt == null ? '—' : p.loadedAt!.toLocal().toString().substring(0, 16)}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                if (legacyBroken) ...[
                                  const SizedBox(width: 8),
                                  const _WarnBadge(text: 'Legacy fix needed'),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      trailing: const Icon(Icons.edit),
                      onTap: () => _adminChangeStatus(context, p),
                      onLongPress: legacyBroken
                          ? () => _repairOne(p)
                          : null, // quick admin fix per item
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _scheduleAutoRepairOnce(List<Property> items) {
    // Only schedule once per screen open; repairs themselves are guarded by _repairedKeys.
    if (_autoRepairScheduled) return;
    _autoRepairScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // Repair a small batch to keep UI responsive.
      // You can adjust the cap; 40 is usually safe.
      const int cap = 40;
      int repaired = 0;

      for (final p in items) {
        if (repaired >= cap) break;
        if (!_isLegacyBrokenLoaded(p)) continue;

        final key = p.key;
        if (_repairedKeys.contains(key)) continue;

        final did = await PropertyService.repairMissingLoadedMilestone(p);
        _repairedKeys.add(key);
        if (did) repaired++;
      }

      // If there are more than cap, admin can press "Repair now" to finish all.
    });
  }

  Future<void> _repairOne(Property p) async {
    final key = p.key;
    if (_repairedKeys.contains(key)) return;

    setState(() => _isRepairing = true);
    try {
      await PropertyService.repairMissingLoadedMilestone(p);
      _repairedKeys.add(key);
    } finally {
      if (mounted) setState(() => _isRepairing = false);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Legacy record repaired ✅')),
    );
  }

  Future<void> _manualRepairAll(Box<Property> box) async {
    if (_isRepairing) return;

    setState(() => _isRepairing = true);
    int repaired = 0;

    try {
      // Make a stable list snapshot (avoid iterating live box while it changes)
      final items = box.values.toList();

      for (final p in items) {
        if (!_isLegacyBrokenLoaded(p)) continue;

        final key = p.key;
        if (_repairedKeys.contains(key)) continue;

        final did = await PropertyService.repairMissingLoadedMilestone(p);
        _repairedKeys.add(key);
        if (did) repaired++;
      }
    } finally {
      if (mounted) setState(() => _isRepairing = false);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          repaired == 0
              ? 'No legacy repairs needed ✅'
              : 'Repaired $repaired legacy record(s) ✅',
        ),
      ),
    );
  }

  Future<void> _adminChangeStatus(BuildContext context, Property p) async {
    if (!RoleGuard.hasRole(UserRole.admin)) return;

    PropertyStatus selected = p.status;

    final result = await showDialog<PropertyStatus>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Admin: Change Status'),
        content: DropdownButtonFormField<PropertyStatus>(
          initialValue: selected,
          items: const [
            DropdownMenuItem(
              value: PropertyStatus.pending,
              child: Text('Pending'),
            ),
            DropdownMenuItem(
              value: PropertyStatus.inTransit,
              child: Text('In Transit'),
            ),
            DropdownMenuItem(
              value: PropertyStatus.delivered,
              child: Text('Delivered'),
            ),
            DropdownMenuItem(
              value: PropertyStatus.pickedUp,
              child: Text('Picked Up'),
            ),
          ],
          onChanged: (v) => selected = v ?? selected,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, selected),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == null) return;

    await PropertyService.adminSetStatus(p, result);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Status updated ✅')),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String text;
  const _StatusChip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.blue.shade50,
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _WarnBadge extends StatelessWidget {
  final String text;
  const _WarnBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.deepOrange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.deepOrange.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.deepOrange,
        ),
      ),
    );
  }
}