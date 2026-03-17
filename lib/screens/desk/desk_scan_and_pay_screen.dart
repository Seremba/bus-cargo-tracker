import 'package:flutter/material.dart';

import '../../models/user_role.dart';
import '../../services/audit_service.dart';
import '../../services/property_lookup_service.dart';
import '../../services/property_service.dart';
import '../../services/role_guard.dart';
import '../../services/session.dart';
import '../common/property_qr_scanner_screen.dart';
import 'desk_record_payment_screen.dart';

class DeskScanAndPayScreen extends StatefulWidget {
  const DeskScanAndPayScreen({super.key});

  @override
  State<DeskScanAndPayScreen> createState() => _DeskScanAndPayScreenState();
}

class _DeskScanAndPayScreenState extends State<DeskScanAndPayScreen> {
  final _manualCode = TextEditingController();

  @override
  void dispose() {
    _manualCode.dispose();
    super.dispose();
  }

  bool get _canUse =>
      RoleGuard.hasAny({UserRole.deskCargoOfficer, UserRole.admin});

  Future<void> _openPropertyByCode(String code) async {
    final clean = code.trim();
    if (clean.isEmpty) return;

    final p = PropertyLookupService.findByPropertyCode(clean);

    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Property not found for code: $clean')),
      );
      return;
    }

    // ── S2: commit-hash verification ─────────────────────────────────────
    // Only verify if the property has been locked (i.e. sender has viewed
    // their QR). Unlocked properties are still being edited by the sender
    // and have no hash yet — let them through normally.
    if (p.isLocked) {
      final hashOk = PropertyService.verifyCommitHash(p);

      if (!hashOk) {
        // Log the tamper event before doing anything else
        await AuditService.log(
          action: 'DESK_SCAN_HASH_MISMATCH',
          propertyKey: p.key.toString(),
          details:
              'Commit-hash mismatch detected at desk scan. '
              'Code=$clean | Officer=${Session.currentUserId ?? "unknown"} '
              '| Station=${Session.currentStationName ?? "unknown"}',
        );

        if (!mounted) return;

        // Block navigation — show a hard warning dialog
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            icon: const Icon(
              Icons.warning_amber_rounded,
              color: Colors.red,
              size: 40,
            ),
            title: const Text(
              'Security Warning',
              style: TextStyle(color: Colors.red),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Property data may have been altered after QR issuance.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 10),
                Text(
                  'The scanned property code does not match the data '
                  'stored on this device. This may mean:\n\n'
                  '• The sender edited receiver details, destination, '
                  'or item count after generating their QR.\n'
                  '• The QR code was modified or forged.\n\n'
                  'Do NOT proceed to payment or loading. '
                  'Contact your admin to investigate.',
                  style: TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Understood — Do Not Proceed'),
              ),
            ],
          ),
        );

        return; // hard block — do not navigate to payment screen
      }
    }
    

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DeskRecordPaymentScreen(property: p)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_canUse) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    final station = Session.currentStationName;
    if (station == null || station.trim().isEmpty) {
      return const Scaffold(
        body: Center(
          child: Text('No station selected. Please select station first.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Payments')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: ListView(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Station: $station',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Scan the Property QR OR type the Property Code manually.',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan Property QR'),
              onPressed: () async {
                final raw = await Navigator.push<String?>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PropertyQrScannerScreen(),
                  ),
                );
                if (raw == null || raw.trim().isEmpty) return;
                await _openPropertyByCode(raw.trim());
              },
            ),

            const SizedBox(height: 16),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Manual entry',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _manualCode,
                      decoration: const InputDecoration(
                        labelText: 'Property code (e.g. P-20260213-8F3K)',
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (v) => _openPropertyByCode(v),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              _manualCode.clear();
                              setState(() {});
                            },
                            child: const Text('Clear'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () =>
                                _openPropertyByCode(_manualCode.text),
                            child: const Text('Continue'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
