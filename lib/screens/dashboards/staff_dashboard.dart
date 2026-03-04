import 'package:flutter/material.dart';

import '../../widgets/logout_button.dart';
import '../../models/staff_station_mode.dart';
import '../staff/staff_station_select_screen.dart';

import '../../services/pickup_qr_service.dart';
import '../staff/staff_pickup_qr_scanner_screen.dart';
import '../staff/staff_confirm_pickup_screen.dart';
import '../../services/session.dart';

class StaffDashboard extends StatelessWidget {
  const StaffDashboard({super.key});

  String _name() => (Session.currentUserFullName ?? 'Staff').trim();

  @override
  Widget build(BuildContext context) {
    final staffName = _name();

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: const Text('Staff'),
          actions: const [LogoutButton()],
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 6),
                  const Icon(
                    Icons.local_shipping_outlined,
                    size: 48,
                    color: Colors.orange,
                  ),
                  const SizedBox(height: 14),

                  // ✅ Make staff name the visual focus
                  Text(
                    staffName.isEmpty ? 'Staff' : staffName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),

                  // ✅ Make dashboard label smaller/secondary
                  Text(
                    'Station Staff Dashboard',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.60),
                    ),
                  ),

                  const SizedBox(height: 26),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Cargo Operations',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          // ✅ Arriving Cargo
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.inventory_2_outlined),
                              label: const Text('Arriving Cargo (Mark Delivered)'),
                              style: ElevatedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const StaffStationSelectScreen(
                                      mode: StaffStationMode.arriving,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),

                          const SizedBox(height: 12),

                          // ✅ OTP Pickup
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.lock_outline),
                              label: const Text('Pickup (Confirm OTP)'),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const StaffStationSelectScreen(
                                      mode: StaffStationMode.pickup,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),

                          const SizedBox(height: 12),

                          // ✅ Scan Pickup QR → parse → open confirm screen
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.qr_code_scanner),
                              label: const Text('Confirm Pickup (Scan QR)'),
                              style: ElevatedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () async {
                                final raw = await Navigator.push<String?>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const StaffPickupQrScannerScreen(),
                                  ),
                                );
                                if (raw == null || raw.trim().isEmpty) return;

                                final parsed =
                                    PickupQrService.parsePayload(raw.trim());
                                if (parsed == null) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Invalid pickup QR'),
                                    ),
                                  );
                                  return;
                                }

                                if (!context.mounted) return;
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => StaffConfirmPickupScreen(
                                      propertyKey: parsed.propertyKey,
                                      nonce: parsed.nonce,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Small hint text (optional but nice)
                  Text(
                    'Tip: Use OTP for manual pickups, or Scan QR for faster confirmation.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}