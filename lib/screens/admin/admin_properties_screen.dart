import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/property.dart';
import '../../models/property_status.dart';
import '../../models/user.dart';
import '../../models/user_role.dart';
import '../../services/hive_service.dart';
import '../../services/property_service.dart';
import '../../services/property_ttl_service.dart';
import '../../services/role_guard.dart';
import 'admin_property_detail_screen.dart';

class AdminPropertiesScreen extends StatefulWidget {
  const AdminPropertiesScreen({super.key});

  @override
  State<AdminPropertiesScreen> createState() => _AdminPropertiesScreenState();
}

class _AdminPropertiesScreenState extends State<AdminPropertiesScreen> {
  final Set<dynamic> _repairedKeys = {};
  bool _autoRepairScheduled = false;
  bool _isRepairing = false;

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

  String _resolveSender(String userId) {
    final raw = userId.trim();
    if (raw.isEmpty) return '—';
    try {
      final user =
          HiveService.userBox().values.firstWhere((u) => u.id == raw);
      final name = user.fullName.trim();
      return name.isEmpty ? 'Unknown sender' : name;
    } catch (_) {
      return 'Sender (not synced)';
    }
  }

  static ({String label, Color bg, Color fg}) _statusStyle(
    PropertyStatus status,
  ) {
    switch (status) {
      case PropertyStatus.pending:
        return (
          label: 'Pending',
          bg: const Color(0xFFFFF8E1),
          fg: const Color(0xFFF57F17),
        );
      case PropertyStatus.loaded:
        return (
          label: 'Loaded',
          bg: const Color(0xFFFFF3E0),
          fg: const Color(0xFFE65100),
        );
      case PropertyStatus.inTransit:
        return (
          label: 'In Transit',
          bg: const Color(0xFFE3F2FD),
          fg: const Color(0xFF1565C0),
        );
      case PropertyStatus.delivered:
        return (
          label: 'Delivered',
          bg: const Color(0xFFE8F5E9),
          fg: const Color(0xFF2E7D32),
        );
      case PropertyStatus.pickedUp:
        return (
          label: 'Picked Up',
          bg: const Color(0xFFE8F5E9),
          fg: const Color(0xFF1B5E20),
        );
      case PropertyStatus.rejected:
        return (
          label: 'Rejected',
          bg: const Color(0xFFFFEBEE),
          fg: const Color(0xFFC62828),
        );
      case PropertyStatus.expired:
        return (
          label: 'Expired',
          bg: const Color(0xFFEFEBE9),
          fg: const Color(0xFF4E342E),
        );
      case PropertyStatus.underReview:
        return (
          label: 'Under Review',
          bg: const Color(0xFFFFF3E0),
          fg: const Color(0xFFFF8F00),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!RoleGuard.hasRole(UserRole.admin)) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    final propertyBox = HiveService.propertyBox();
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.55);

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
            onPressed: _isRepairing
                ? null
                : () => _manualRepairAll(propertyBox),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          propertyBox.listenable(),
          HiveService.userBox().listenable(),
        ]),
        builder: (context, _) {
          final items = propertyBox.values.toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          if (items.isEmpty) {
            return const Center(child: Text('No properties yet.'));
          }

          _scheduleAutoRepairOnce(items);

          final brokenCount = items.where(_isLegacyBrokenLoaded).length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              if (brokenCount > 0)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: cs.tertiary.withValues(alpha: 0.12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: cs.tertiary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '$brokenCount old record(s) missing Loaded milestone.',
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _isRepairing
                              ? null
                              : () => _manualRepairAll(propertyBox),
                          icon: const Icon(Icons.build, size: 18),
                          label: const Text('Repair'),
                        ),
                      ],
                    ),
                  ),
                ),
              for (final p in items) _propertyCard(context, p, cs, muted),
            ],
          );
        },
      ),
    );
  }

  Widget _propertyCard(
    BuildContext context,
    Property p,
    ColorScheme cs,
    Color muted,
  ) {
    final style = _statusStyle(p.status);
    final legacyBroken = _isLegacyBrokenLoaded(p);
    final routeText = p.routeName.trim().isEmpty ? '—' : p.routeName.trim();
    final senderName = _resolveSender(p.createdByUserId);

    final loadedDone =
        p.loadedAt != null ||
        p.status == PropertyStatus.inTransit ||
        p.status == PropertyStatus.delivered ||
        p.status == PropertyStatus.pickedUp;

    final showLoadedRow =
        p.loadedAt != null ||
        p.status == PropertyStatus.inTransit ||
        p.status == PropertyStatus.delivered ||
        p.status == PropertyStatus.pickedUp;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _handleCardTap(context, p),
        onLongPress: legacyBroken ? () => _repairOne(p) : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      p.receiverName.trim().isEmpty ? '—' : p.receiverName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: style.bg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      style.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: style.fg,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _handleEditTap(context, p),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.edit_outlined, size: 18, color: muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '📍 ${p.destination.trim().isEmpty ? '—' : p.destination}  •  ${p.receiverPhone.trim().isEmpty ? '—' : p.receiverPhone}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${p.itemCount} item${p.itemCount == 1 ? '' : 's'}  •  $routeText',
                style: TextStyle(fontSize: 12, color: muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                p.description.trim().isEmpty ? '—' : p.description.trim(),
                style: TextStyle(fontSize: 12, color: muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                'Sender: $senderName',
                style: TextStyle(fontSize: 12, color: muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                'Created: ${_fmt16(p.createdAt)}',
                style: TextStyle(fontSize: 12, color: muted),
              ),

              // ── Under Review banner ─────────────────────────────────
              if (p.status == PropertyStatus.underReview) ...[
                const SizedBox(height: 6),
                _infoBanner(
                  color: const Color(0xFFFF8F00),
                  bg: const Color(0xFFFFF3E0),
                  title: 'Re-review requested by sender',
                  body:
                      'Original rejection: ${PropertyService.rejectionCategoryLabel(p.rejectionCategory ?? 'other')}'
                      '${(p.rejectionReason ?? '').trim().isEmpty ? '' : ' — ${p.rejectionReason!.trim()}'}\n'
                      'Tap to Approve (restore to Pending) or Deny.',
                ),
              ],

              // ── Rejection banner ────────────────────────────────────
              if (p.status == PropertyStatus.rejected) ...[
                const SizedBox(height: 6),
                _infoBanner(
                  color: const Color(0xFFC62828),
                  bg: const Color(0xFFFFEBEE),
                  title:
                      'Rejected: ${PropertyService.rejectionCategoryLabel(p.rejectionCategory ?? '')}',
                  body: (p.rejectionReason ?? '').trim(),
                ),
              ],

              // ── Expired banner ──────────────────────────────────────
              if (p.status == PropertyStatus.expired) ...[
                const SizedBox(height: 6),
                _infoBanner(
                  color: const Color(0xFF4E342E),
                  bg: const Color(0xFFEFEBE9),
                  title: 'Expired — no payment recorded within 10 days',
                  body: 'Tap to restore to Pending.',
                ),
              ],

              if (showLoadedRow) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      loadedDone
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 15,
                      color: loadedDone ? Colors.green : muted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Loaded: ${_fmt16(p.loadedAt)}',
                        style: TextStyle(fontSize: 12, color: muted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (legacyBroken) ...[
                      const SizedBox(width: 8),
                      _WarnBadge(text: 'Legacy fix needed'),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoBanner({
    required Color color,
    required Color bg,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          if (body.isNotEmpty)
            Text(body, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }

  Future<void> _handleCardTap(BuildContext context, Property p) async {
    if (!RoleGuard.hasRole(UserRole.admin)) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminPropertyDetailScreen(property: p),
      ),
    );
  }

  Future<void> _handleEditTap(BuildContext context, Property p) async {
    if (!RoleGuard.hasRole(UserRole.admin)) return;

    switch (p.status) {
      case PropertyStatus.underReview:
        await _adminReviewDialog(context, p);
      case PropertyStatus.rejected:
        await _adminChangeStatusRejected(context, p);
      case PropertyStatus.expired:
        await _adminRestoreExpired(context, p);
      default:
        await _adminChangeStatus(context, p);
    }
  }

  // ── Under Review: Approve / Deny ────────────────────────────────────────
  Future<void> _adminReviewDialog(BuildContext context, Property p) async {
    final denyNoteController = TextEditingController();

    // Pull the change summary from the most recent PROPERTY_EDITED_AFTER_REJECTION
    // audit event for this property key.
    final auditBox = HiveService.auditBox();
    final propKeyStr = p.key.toString();
    final editEvents =
        auditBox.values
            .where(
              (e) =>
                  e.propertyKey == propKeyStr &&
                  e.action == 'PROPERTY_EDITED_AFTER_REJECTION',
            )
            .toList()
          ..sort((a, b) => b.at.compareTo(a.at));

    // Extract the "Changes: ..." line from the most recent edit event details
    String changeSummary = '';
    if (editEvents.isNotEmpty) {
      final details = editEvents.first.details ?? '';
      final idx = details.indexOf('Changes:');
      if (idx != -1) {
        changeSummary = details.substring(idx + 'Changes:'.length).trim();
      }
    }

    final result = await showDialog<_ReviewAction>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Review Re-Review Request'),
        // SingleChildScrollView prevents overflow when the soft keyboard appears
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Property ${p.propertyCode.trim().isEmpty ? p.key.toString() : p.propertyCode} '
                  'for ${p.receiverName}.',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  'Original rejection: ${PropertyService.rejectionCategoryLabel(p.rejectionCategory ?? 'other')}',
                ),
                if ((p.rejectionReason ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    p.rejectionReason!.trim(),
                    style: const TextStyle(fontSize: 13),
                  ),
                ],

                // ── What the sender changed ──────────────────────────
                if (changeSummary.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F8FF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF1565C0).withValues(alpha: 0.25),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Sender edits:',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1565C0),
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Each change is separated by ", " — show one per line
                        ...changeSummary
                            .split(', ')
                            .map(
                              (line) => Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  '• $line',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF1565C0),
                                  ),
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 6),
                  const Text(
                    'No recorded edits found.',
                    style: TextStyle(fontSize: 12, color: Colors.black45),
                  ),
                ],

                const SizedBox(height: 16),
                const Text(
                  'Optional note for sender (shown on deny):',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: denyNoteController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Rejection upheld — prohibited item',
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, _ReviewAction.deny),
            child: const Text('Deny'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, _ReviewAction.approve),
            child: const Text('Approve → Pending'),
          ),
        ],
      ),
    );

    if (result == null || !context.mounted) return;

    if (result == _ReviewAction.approve) {
      final ok = await PropertyService.adminRestoreRejected(p);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Approved — property restored to Pending ✅'
                : 'Could not approve ❌',
          ),
        ),
      );
    } else {
      final note = denyNoteController.text.trim();
      final ok = await PropertyService.adminDenyReReview(p, note: note);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Re-review denied — property stays Rejected ✅'
                : 'Could not deny ❌',
          ),
        ),
      );
    }
  }

  // ── Expired restore ─────────────────────────────────────────────────────
  Future<void> _adminRestoreExpired(BuildContext context, Property p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restore Expired Property'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${p.propertyCode.trim().isEmpty ? 'This property' : p.propertyCode} '
              'expired after 10 days with no payment recorded.',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const Text(
              'Restoring will set the property back to Pending. '
              'The sender will be notified and must complete payment at the desk.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore to Pending'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    final ok = await PropertyTtlService.adminRestoreExpired(p);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Property restored to Pending ✅' : 'Could not restore ❌',
        ),
      ),
    );
  }

  // ── Rejected restore (direct, no re-review flow) ────────────────────────
  Future<void> _adminChangeStatusRejected(
    BuildContext context,
    Property p,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restore Rejected Property'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rejection reason: ${PropertyService.rejectionCategoryLabel(p.rejectionCategory ?? '')}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if ((p.rejectionReason ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(p.rejectionReason!.trim()),
            ],
            const SizedBox(height: 12),
            const Text(
              'Restoring will set the property back to Pending and allow '
              'the sender to re-present it at the desk. All items will be reset for re-loading.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore to Pending'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    await PropertyService.adminRestoreRejected(p);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Property restored to Pending ✅')),
    );
  }

  // ── Generic status change ───────────────────────────────────────────────
  Future<void> _adminChangeStatus(BuildContext context, Property p) async {
    if (!RoleGuard.hasRole(UserRole.admin)) return;

    PropertyStatus selected = p.status;

    final result = await showDialog<PropertyStatus>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Change Status'),
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
            // rejected, expired, underReview are not offered here —
            // they have dedicated dialogs
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
      for (final p in box.values.toList()) {
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
}

enum _ReviewAction { approve, deny }

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