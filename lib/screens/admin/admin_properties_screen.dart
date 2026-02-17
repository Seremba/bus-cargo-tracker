import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/property.dart';
import '../../models/property_status.dart';
import '../../models/user_role.dart';
import '../../services/hive_service.dart';
import '../../services/property_service.dart';
import '../../services/role_guard.dart';

class AdminPropertiesScreen extends StatelessWidget {
  const AdminPropertiesScreen({super.key});

  Widget _notAuthorized() =>
      const Scaffold(body: Center(child: Text('Not authorized')));

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

  @override
  Widget build(BuildContext context) {
    if (!RoleGuard.hasRole(UserRole.admin)) return _notAuthorized();

    final box = HiveService.propertyBox();

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        elevation: 2,
        title: const Text('All Properties'),
      ),
      body: ValueListenableBuilder(
        valueListenable: box.listenable(),
        builder: (context, Box<Property> box, _) {
          final items = box.values.toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          if (items.isEmpty) {
            return const Center(child: Text('No properties yet.'));
          }

          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final p = items[index];

              // If your model fields are non-nullable, these still work fine.
              final routeText = _dashIfEmpty(p.routeName);
              final senderText = _dashIfEmpty(p.createdByUserId);

              return Card(
                margin: const EdgeInsets.all(8),
                child: ListTile(
                  title: Text(_s(p.receiverName)),
                  subtitle: Column(
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
                        _statusText(p.status),
                        style: const TextStyle(fontWeight: FontWeight.w600),
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
                    ],
                  ),
                  trailing: const Icon(Icons.edit),
                  onTap: () {
                    // guard already above; keep this simple
                    _adminChangeStatus(context, p);
                  },
                ),
              );
            },
          );
        },
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
