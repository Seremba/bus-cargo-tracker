import 'package:flutter/material.dart';

import '../../widgets/logout_button.dart';
import '../../models/staff_station_mode.dart';
import '../staff/staff_station_select_screen.dart';

import '../../services/pickup_qr_service.dart';
import '../staff/staff_pickup_qr_scanner_screen.dart';
import '../staff/staff_confirm_pickup_screen.dart';

class StaffDashboard extends StatelessWidget {
  const StaffDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Staff Dashboard'),
          actions: const [LogoutButton()],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Welcome, Store staff',
                style: TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
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
                  child: const Text('Arriving Cargo (Mark Delivered)'),
                ),
              ),

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
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
                  child: const Text('Pickup (Confirm OTP)'),
                ),
              ),

              const SizedBox(height: 12),

              // Scan Pickup QR → parse → open confirm screen
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Confirm Pickup (Scan QR)'),
                  onPressed: () async {
                    final raw = await Navigator.push<String?>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const StaffPickupQrScannerScreen(),
                      ),
                    );
                    if (raw == null || raw.trim().isEmpty) return;

                    final parsed = PickupQrService.parsePayload(raw.trim());
                    if (parsed == null) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Invalid pickup QR')),
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
    );
  }
}
