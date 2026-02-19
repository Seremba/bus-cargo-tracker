import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/property.dart';
import '../../models/property_status.dart';
import '../../models/user_role.dart';

import '../../services/hive_service.dart';
import '../../services/role_guard.dart';
import '../../services/property_label_service.dart';
import '../../services/property_service.dart';
import '../../services/session.dart';

import '../../services/printing/escpos_label_builder.dart';


class DeskPropertyDetailsScreen extends StatelessWidget {
  final String scannedCode; // propertyCode
  const DeskPropertyDetailsScreen({super.key, required this.scannedCode});

  static String _fmt16(DateTime? d) {
    if (d == null) return '—';
    return d.toLocal().toString().substring(0, 16);
  }

  String _statusText(PropertyStatus s) {
    switch (s) {
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

  Property? _findByCode(Box<Property> box, String code) {
    final c = code.trim().toLowerCase();
    if (c.isEmpty) return null;

    // primary: propertyCode
    for (final p in box.values) {
      if (p.propertyCode.trim().toLowerCase() == c) return p;
    }

    // fallback: allow scanning "key" if someone encoded it
    final key = int.tryParse(code.trim());
    if (key != null) return box.get(key);

    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (!RoleGuard.hasAny({UserRole.deskCargoOfficer, UserRole.admin})) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    final box = HiveService.propertyBox();

    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Scanned Property')),
      body: ValueListenableBuilder(
        valueListenable: box.listenable(),
        builder: (context, Box<Property> b, _) {
          final p = _findByCode(b, scannedCode);

          if (p == null) {
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Property not found for code:\n\n$scannedCode',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            );
          }

          final code = p.propertyCode.trim().isEmpty
              ? p.key.toString()
              : p.propertyCode.trim();

          // ✅ Desk action allowed only before transit
          final canMarkLoaded =
              p.status == PropertyStatus.pending && p.loadedAt == null;

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Code: $code',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('Status: ${_statusText(p.status)}'),
                      Text('Receiver: ${p.receiverName}'),
                      Text('Phone: ${p.receiverPhone}'),
                      Text('Destination: ${p.destination}'),
                      Text('Items: ${p.itemCount}'),
                      const SizedBox(height: 6),
                      Text(
                        'Created: ${_fmt16(p.createdAt)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        'Loaded: ${_fmt16(p.loadedAt)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        'InTransit: ${_fmt16(p.inTransitAt)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        'Delivered: ${_fmt16(p.deliveredAt)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ✅ Mark Loaded (Desk) — persists loadedAt fields
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.local_shipping),
                  label: Text(
                    canMarkLoaded ? 'Mark Loaded (Desk)' : 'Loaded ✅',
                  ),
                  onPressed: !canMarkLoaded
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final st = (Session.currentStationName ?? '').trim();

                          if (st.isEmpty) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('No station set for this user ❌'),
                              ),
                            );
                            return;
                          }

                          final ok = await PropertyService.markLoaded(
                            p,
                            station: st,
                          );

                          if (!context.mounted) return;

                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                ok ? 'Marked Loaded ✅' : 'Cannot mark loaded ❌',
                              ),
                            ),
                          );
                        },
                ),
              ),

              const SizedBox(height: 12),

              // ✅ Share / Print Label
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.print),
                  label: const Text('Print Thermal Label (58mm)'),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      final bytes =
                          await EscPosLabelBuilder.buildPropertyLabel58(
                            property,
                          );
                      final ok = await PrinterService.printBytesBluetooth(
                        bytes,
                      );
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(ok ? 'Printed ✅' : 'Print failed ❌'),
                        ),
                      );
                    } catch (e) {
                      messenger.showSnackBar(
                        SnackBar(content: Text('Print error: $e')),
                      );
                    }
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
