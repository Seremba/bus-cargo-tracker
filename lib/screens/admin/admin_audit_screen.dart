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

  @override
  Widget build(BuildContext context) {
    // ✅ UI RoleGuard
    if (!RoleGuard.hasRole(UserRole.admin)) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    final box = HiveService.auditBox();

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Audit Log'),
        actions: [
          IconButton(icon: const Icon(Icons.date_range), onPressed: _pickRange),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: box.listenable(),
        builder: (context, Box<AuditEvent> b, _) {
          final all = b.values.toList()..sort((a, b) => b.at.compareTo(a.at));

          final filtered = all.where((e) {
            final actionOk =
                _actionFilter == 'ALL' || e.action == _actionFilter;

            final roleOk = _roleFilter == 'ALL' || e.actorRole == _roleFilter;

            final dateOk = _inRange(e.at);

            return actionOk && roleOk && dateOk;
          }).toList();

          return Column(
            children: [
              _filters(),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('No audit events found.'))
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final e = filtered[i];

                          return Card(
                            margin: const EdgeInsets.all(8),
                            child: ListTile(
                              title: Text(e.action),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Time: ${e.at.toLocal().toString().substring(0, 19)}',
                                  ),
                                  if (e.actorUserId != null)
                                    Text('User: ${e.actorUserId}'),
                                  if (e.actorRole != null)
                                    Text('Role: ${e.actorRole}'),
                                  if (e.propertyKey != null)
                                    Text('Property: ${e.propertyKey}'),
                                  if (e.tripId != null)
                                    Text('Trip: ${e.tripId}'),
                                  if (e.details != null &&
                                      e.details!.trim().isNotEmpty)
                                    Text('Details: ${e.details}'),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _filters() {
  return Padding(
    padding: const EdgeInsets.all(8),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 520;

        final actionDropdown = DropdownButtonFormField<String>(
          isExpanded: true, // ✅ important
          initialValue: _actionFilter,
          decoration: const InputDecoration(
            labelText: 'Action',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'ALL', child: Text('All')),
            DropdownMenuItem(
              value: 'staff_mark_delivered',
              child: Text('Staff: Mark Delivered'),
            ),
            DropdownMenuItem(
              value: 'staff_confirm_pickup_ok',
              child: Text('Staff: Pickup OK'),
            ),
            DropdownMenuItem(
              value: 'staff_confirm_pickup_failed',
              child: Text('Staff: Pickup Failed'),
            ),
            DropdownMenuItem(
              value: 'admin_unlock_otp',
              child: Text('Admin: Unlock OTP'),
            ),
            DropdownMenuItem(
              value: 'admin_reset_otp',
              child: Text('Admin: Reset OTP'),
            ),
          ],
          onChanged: (v) => setState(() => _actionFilter = v ?? 'ALL'),
        );

        final roleDropdown = DropdownButtonFormField<String>(
          isExpanded: true, // ✅ important
          initialValue: _roleFilter,
          decoration: const InputDecoration(
            labelText: 'Actor Role',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'ALL', child: Text('All')),
            DropdownMenuItem(value: 'admin', child: Text('Admin')),
            DropdownMenuItem(value: 'desk', child: Text('Desk Cargo Officer')),
            DropdownMenuItem(value: 'staff', child: Text('Staff')),
            DropdownMenuItem(value: 'driver', child: Text('Driver')),
            DropdownMenuItem(value: 'sender', child: Text('Sender')),
          ],
          onChanged: (v) => setState(() => _roleFilter = v ?? 'ALL'),
        );

        if (isNarrow) {
          // ✅ stack vertically on small widths
          return Column(
            children: [
              actionDropdown,
              const SizedBox(height: 12),
              roleDropdown,
            ],
          );
        }

        // ✅ side-by-side on wide widths
        return Row(
          children: [
            Expanded(child: actionDropdown),
            const SizedBox(width: 8),
            Expanded(child: roleDropdown),
          ],
        );
      },
    ),
  );
}

}
