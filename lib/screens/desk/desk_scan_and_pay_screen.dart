import 'package:flutter/material.dart';

import '../../models/user_role.dart';
import '../../services/property_lookup_service.dart';
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

  bool get _canUse => RoleGuard.hasAny({UserRole.deskCargoOfficer, UserRole.admin});

  void _openPropertyByCode(String code) {
    final clean = code.trim();
    if (clean.isEmpty) return;

    final p = PropertyLookupService.findByPropertyCode(clean);

    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Property not found for code: $clean')),
      );
      return;
    }

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
        body: Center(child: Text('No station selected. Please select station first.')),
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
                    Text('Station: $station',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
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
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan Property QR'),
              onPressed: () async {
                final raw = await Navigator.push<String?>(
                  context,
                  MaterialPageRoute(builder: (_) => const PropertyQrScannerScreen()),
                );
                if (raw == null || raw.trim().isEmpty) return;

                _openPropertyByCode(raw.trim());
              },
            ),

            const SizedBox(height: 16),

            // ✅ Manual entry fallback
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Manual entry',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _manualCode,
                      decoration: const InputDecoration(
                        labelText: 'Property code (e.g. P-20260213-8F3K)',
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.done,
                      onSubmitted: _openPropertyByCode,
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
                            onPressed: () => _openPropertyByCode(_manualCode.text),
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
