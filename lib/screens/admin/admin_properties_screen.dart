import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/property.dart';
import '../../models/property_status.dart';
import '../../models/user_role.dart';
import '../../services/hive_service.dart';
import '../../services/property_service.dart';
import '../../services/role_guard.dart';

import '../../theme/status_colors.dart';
import '../../widgets/status_chip.dart';

import '../../ui/status_labels.dart';

class AdminPropertiesScreen extends StatefulWidget {
  const AdminPropertiesScreen({super.key});

  @override
  State<AdminPropertiesScreen> createState() => _AdminPropertiesScreenState();
}

class _AdminPropertiesScreenState extends State<AdminPropertiesScreen> {
  final Set<dynamic> _repairedKeys = <dynamic>{};

  bool _autoRepairScheduled = false;
  bool _isRepairing = false;

  String _s(String? v) => v ?? '';

  String _dashIfEmpty(String? v) {
    final t = (v ?? '').trim();
    return t.isEmpty ? '—' : t;
  }

  String _fmt16(DateTime? d) {
    if (d == null) return '—';
    final s = d.toLocal().toString();
    return s.length >= 16 ? s.substring(0, 16) : s;
  }

  bool _isLegacyBrokenLoaded(Property p) {
    final impliesLoaded =
        p.status == PropertyStatus.inTransit ||
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
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.60);

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
                  color: cs.tertiary.withValues(alpha: 0.12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: cs.tertiary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '$brokenCount old record(s) are missing Loaded milestone.\n'
                            'They will be repaired automatically when you open this screen.',
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _isRepairing
                              ? null
                              : () => _manualRepairAll(box),
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

                  final legacyBroken = _isLegacyBrokenLoaded(p);
                  final loadedDone =
                      p.loadedAt != null ||
                      p.status == PropertyStatus.inTransit ||
                      p.status == PropertyStatus.delivered ||
                      p.status == PropertyStatus.pickedUp;

                  final bg = PropertyStatusColors.background(p.status);
                  final fg = PropertyStatusColors.foreground(p.status);

                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _s(p.receiverName),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          StatusChip(
                            text: PropertyStatusLabels.text(p.status),
                            bgColor: bg,
                            fgColor: fg,
                          ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_s(p.destination)} • ${_s(p.receiverPhone)}',
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Items: ${p.itemCount} • Route: $routeText',
                              style: TextStyle(fontSize: 12, color: muted),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Sender: $senderText',
                              style: TextStyle(fontSize: 12, color: muted),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Created: ${_fmt16(p.createdAt)}',
                              style: TextStyle(fontSize: 12, color: muted),
                            ),
                            const SizedBox(height: 10),

                            Row(
                              children: [
                                Icon(
                                  loadedDone
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  size: 16,
                                  color: loadedDone ? cs.primary : muted,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Loaded: ${_fmt16(p.loadedAt)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: muted,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
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
                      onLongPress: legacyBroken ? () => _repairOne(p) : null,
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
    if (_autoRepairScheduled) return;
    _autoRepairScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Legacy record repaired ✅')));
  }

  Future<void> _manualRepairAll(Box<Property> box) async {
    if (_isRepairing) return;

    setState(() => _isRepairing = true);
    int repaired = 0;

    try {
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
              value: PropertyStatus.loaded,
              child: Text('Loaded'),
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Status updated ✅')));
  }
}

class _WarnBadge extends StatelessWidget {
  final String text;
  const _WarnBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.error.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: cs.error,
        ),
      ),
    );
  }
}
