import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/audit_event.dart';
import '../../services/hive_service.dart';
import '../../services/role_guard.dart';
import '../../models/user_role.dart';

class AdminAuditScreen extends StatefulWidget {
  const AdminAuditScreen({super.key});

  @override
  State<AdminAuditScreen> createState() => _AdminAuditScreenState();
}

class _AdminAuditScreenState extends State<AdminAuditScreen> {
  String _actionFilter = 'ALL';
  String _roleFilter = 'ALL';
  DateTime? _start;
  DateTime? _end;

  bool _inRange(DateTime dt) {
    if (_start == null || _end == null) return true;
    final d = DateTime(dt.year, dt.month, dt.day);
    return !d.isBefore(_start!) && !d.isAfter(_end!);
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
    );
    if (picked == null) return;
    setState(() {
      _start = DateTime(
        picked.start.year,
        picked.start.month,
        picked.start.day,
      );
      _end = DateTime(picked.end.year, picked.end.month, picked.end.day);
    });
  }

  // Human-readable action labels
  static String _actionLabel(String action) {
    const map = {
      'desk_mark_loaded_items': 'Items Loaded',
      'PAYMENT_RECORDED': 'Payment Recorded',
      'PROPERTY_REGISTERED': 'Property Registered',
      'staff_mark_delivered': 'Marked Delivered',
      'staff_confirm_pickup_ok': 'Pickup Confirmed',
      'staff_confirm_pickup_failed': 'Pickup Failed',
      'admin_unlock_otp': 'OTP Unlocked',
      'admin_reset_otp': 'OTP Reset',
      'admin_set_status': 'Status Override',
      'auto_repair_missing_loadedAt': 'Auto Repair',
      'receiver_notify_failed': 'Notify Failed',
      'OTP_SMS_QUEUED': 'OTP SMS Queued',
      'OTP_SMS_SKIPPED_DUPLICATE': 'OTP SMS Skipped',
      'OTP_SMS_QUEUE_FAILED': 'OTP SMS Failed',
      'property_in_transit_no_items_moved': 'No Items Moved',
    };
    return map[action] ?? action.replaceAll('_', ' ');
  }

  // Human-readable role labels
  static String _roleLabel(String? role) {
    if (role == null || role.trim().isEmpty) return '—';
    const map = {
      'admin': 'Admin',
      'staff': 'Staff',
      'driver': 'Driver',
      'sender': 'Sender',
      'deskCargoOfficer': 'Desk Cargo Officer',
      'desk': 'Desk Cargo Officer',
    };
    return map[role] ?? role;
  }

  // Resolve userId → full name
  String _resolveUser(String? userId) {
    final raw = (userId ?? '').trim();
    if (raw.isEmpty) return '—';
    try {
      final user =
          HiveService.userBox().values.firstWhere((u) => u.id == raw);
      final name = user.fullName.trim();
      return name.isEmpty ? raw : name;
    } catch (_) {
      return raw;
    }
  }

  // Resolve propertyKey → property code
  String _resolveProperty(String? propertyKey) {
    final raw = (propertyKey ?? '').trim();
    if (raw.isEmpty) return '—';
    try {
      final key = int.tryParse(raw);
      if (key == null) return raw;
      final prop = HiveService.propertyBox().get(key);
      if (prop == null) return raw;
      final code = prop.propertyCode.trim();
      return code.isEmpty ? raw : code;
    } catch (_) {
      return raw;
    }
  }

  // Clean up raw details string
  static String _cleanDetails(String? details) {
    if (details == null || details.trim().isEmpty) return '';
    // Remove trailing "Note=" or "Note= " patterns
    var d = details.trim();
    d = d.replaceAll(RegExp(r'\s*Note=\s*$'), '');
    d = d.replaceAll(RegExp(r'\s*Note=$'), '');
    return d.trim();
  }

  // Action chip color
  static Color _actionColor(String action) {
    if (action.contains('PAYMENT') || action.contains('payment')) {
      return Colors.green.shade700;
    }
    if (action.contains('REGISTERED') || action.contains('registered')) {
      return Colors.blue.shade700;
    }
    if (action.contains('loaded') || action.contains('LOADED')) {
      return const Color(0xFFE65100);
    }
    if (action.contains('delivered') || action.contains('DELIVERED')) {
      return Colors.teal.shade700;
    }
    if (action.contains('pickup') || action.contains('PICKUP')) {
      return Colors.green.shade800;
    }
    if (action.contains('failed') || action.contains('FAILED')) {
      return Colors.red.shade600;
    }
    if (action.contains('admin') || action.contains('ADMIN')) {
      return const Color(0xFF4527A0);
    }
    if (action.contains('repair') || action.contains('REPAIR')) {
      return Colors.orange.shade700;
    }
    return Colors.grey.shade600;
  }

  @override
  Widget build(BuildContext context) {
    if (!RoleGuard.hasRole(UserRole.admin)) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    final box = HiveService.auditBox();
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.55);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Audit Log'),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            tooltip: 'Filter by date range',
            onPressed: _pickRange,
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          box.listenable(),
          HiveService.userBox().listenable(),
          HiveService.propertyBox().listenable(),
        ]),
        builder: (context, _) {
          final all = box.values.toList()..sort((a, b) => b.at.compareTo(a.at));

          final filtered = all.where((e) {
            final actionOk =
                _actionFilter == 'ALL' || e.action == _actionFilter;
            final roleOk = _roleFilter == 'ALL' || e.actorRole == _roleFilter;
            final dateOk = _inRange(e.at);
            return actionOk && roleOk && dateOk;
          }).toList();

          return Column(
            children: [
              _filtersBar(cs, muted),
              // Date range strip
              if (_start != null && _end != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  color: cs.primary.withValues(alpha: 0.07),
                  child: Row(
                    children: [
                      Icon(Icons.date_range, size: 14, color: cs.primary),
                      const SizedBox(width: 6),
                      Text(
                        '${_start!.toString().substring(0, 10)} → ${_end!.toString().substring(0, 10)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => setState(() {
                          _start = null;
                          _end = null;
                        }),
                        child: Icon(Icons.close, size: 16, color: cs.primary),
                      ),
                    ],
                  ),
                ),
              // Count strip
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    Text(
                      '${filtered.length} event${filtered.length == 1 ? '' : 's'}',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          'No audit events found.',
                          style: TextStyle(color: muted),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final e = filtered[i];
                          return _auditCard(e, cs, muted);
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _filtersBar(ColorScheme cs, Color muted) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Row(
        children: [
          // Action filter chip
          Expanded(
            child: _compactDropdown(
              label: 'Action',
              value: _actionFilter,
              items: const [
                DropdownMenuItem(value: 'ALL', child: Text('All actions')),
                DropdownMenuItem(
                  value: 'desk_mark_loaded_items',
                  child: Text('Items Loaded'),
                ),
                DropdownMenuItem(
                  value: 'PAYMENT_RECORDED',
                  child: Text('Payment Recorded'),
                ),
                DropdownMenuItem(
                  value: 'PROPERTY_REGISTERED',
                  child: Text('Property Registered'),
                ),
                DropdownMenuItem(
                  value: 'staff_mark_delivered',
                  child: Text('Marked Delivered'),
                ),
                DropdownMenuItem(
                  value: 'staff_confirm_pickup_ok',
                  child: Text('Pickup Confirmed'),
                ),
                DropdownMenuItem(
                  value: 'admin_set_status',
                  child: Text('Status Override'),
                ),
                DropdownMenuItem(
                  value: 'admin_reset_otp',
                  child: Text('OTP Reset'),
                ),
              ],
              onChanged: (v) => setState(() => _actionFilter = v ?? 'ALL'),
            ),
          ),
          const SizedBox(width: 8),
          // Role filter
          Expanded(
            child: _compactDropdown(
              label: 'Role',
              value: _roleFilter,
              items: const [
                DropdownMenuItem(value: 'ALL', child: Text('All roles')),
                DropdownMenuItem(value: 'admin', child: Text('Admin')),
                DropdownMenuItem(
                  value: 'deskCargoOfficer',
                  child: Text('Desk Officer'),
                ),
                DropdownMenuItem(value: 'staff', child: Text('Staff')),
                DropdownMenuItem(value: 'driver', child: Text('Driver')),
                DropdownMenuItem(value: 'sender', child: Text('Sender')),
              ],
              onChanged: (v) => setState(() => _roleFilter = v ?? 'ALL'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactDropdown({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 12),
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        filled: true,
        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.30),
      ),
      dropdownColor: cs.surface,
      items: items.map((item) => DropdownMenuItem<String>(
        value: item.value,
        child: DefaultTextStyle(
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurface,
          ),
          child: item.child,
        ),
      )).toList(),
      onChanged: onChanged,
      style: TextStyle(fontSize: 12, color: cs.onSurface),
    );
  }

  Widget _auditCard(AuditEvent e, ColorScheme cs, Color muted) {
    final actionLabel = _actionLabel(e.action);
    final actionColor = _actionColor(e.action);
    final userName = _resolveUser(e.actorUserId);
    final roleLabel = _roleLabel(e.actorRole);
    final propertyCode = _resolveProperty(e.propertyKey);
    final details = _cleanDetails(e.details);
    final time = e.at.toLocal().toString().substring(0, 19);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Colored action pill
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: actionColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: actionColor.withValues(alpha: 0.30),
                    ),
                  ),
                  child: Text(
                    actionLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: actionColor,
                    ),
                  ),
                ),
                const Spacer(),
                // Time top-right
                Text(time, style: TextStyle(fontSize: 11, color: muted)),
              ],
            ),

            const SizedBox(height: 8),
            Divider(
              height: 1,
              color: cs.outlineVariant.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 8),

            _detailRow(
              icon: Icons.person_outline,
              text: '$userName  •  $roleLabel',
              muted: muted,
            ),

            if ((e.propertyKey ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              _detailRow(
                icon: Icons.inventory_2_outlined,
                text: 'Property: $propertyCode',
                muted: muted,
              ),
            ],

            if ((e.tripId ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              _detailRow(
                icon: Icons.local_shipping_outlined,
                text: 'Trip: ${e.tripId}',
                muted: muted,
              ),
            ],

            if (details.isNotEmpty) ...[
              const SizedBox(height: 4),
              _detailRow(
                icon: Icons.notes_outlined,
                text: details,
                muted: muted,
                maxLines: 3,
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Widget _detailRow({
    required IconData icon,
    required String text,
    required Color muted,
    int maxLines = 1,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 13, color: muted),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, color: muted),
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}