import 'package:bus_cargo_tracker/ui/app_colors.dart';
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

  // Initials avatar helper
  Widget _initialsAvatar(String fullName) {
    final parts = fullName.trim().split(' ');
    final initials = parts.length >= 2
        ? '${parts.first[0]}${parts.last[0]}'.toUpperCase()
        : fullName.isNotEmpty
        ? fullName.substring(0, fullName.length.clamp(0, 2)).toUpperCase()
        : 'ST';
    // Staff role color: blue
    const color = Colors.blue;
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 28,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final staffName = _name();
    final cs = Theme.of(context).colorScheme;

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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ── Initials avatar (replaces generic truck icon) ──
                  _initialsAvatar(staffName.isEmpty ? 'Staff' : staffName),
                  const SizedBox(height: 14),

                  // ── Staff name ──
                  Text(
                    staffName.isEmpty ? 'Staff' : staffName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),

                  // ── Role badge ──
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Station Staff',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue,
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),

                  // ── Section title: 3px primary left border + icon + bold ──
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        Container(
                          width: 3,
                          height: 20,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.local_shipping_outlined,
                          size: 17,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Cargo Operations',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ── Operations card ──
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          // Arriving Cargo → Mark Delivered
                          _dashButton(
                            context: context,
                            icon: Icons.inventory_2_outlined,
                            label: 'Arriving Cargo (Mark Delivered)',
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const StaffStationSelectScreen(
                                  mode: StaffStationMode.arriving,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Pickup — Confirm OTP (outlined, primary-colored)
                          _dashButtonOutlined(
                            context: context,
                            icon: Icons.lock_outline,
                            label: 'Pickup (Confirm OTP)',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const StaffStationSelectScreen(
                                  mode: StaffStationMode.pickup,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Confirm Pickup via QR scan
                          _dashButton(
                            context: context,
                            icon: Icons.qr_code_scanner_outlined,
                            label: 'Confirm Pickup (Scan QR)',
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            onTap: () async {
                              final raw = await Navigator.push<String?>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const StaffPickupQrScannerScreen(),
                                ),
                              );
                              if (raw == null || raw.trim().isEmpty) return;

                              final parsed = PickupQrService.parsePayload(
                                raw.trim(),
                              );
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
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Tip row: icon + text (never plain text alone) ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 14,
                        color: cs.onSurface.withValues(alpha: 0.45),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Use OTP for manual pickups, or Scan QR for faster confirmation.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Filled dashboard button ──
  Widget _dashButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color backgroundColor,
    required Color foregroundColor,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: Icon(icon, size: 20),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: onTap,
      ),
    );
  }

  // ── Outlined dashboard button (primary color) ──
  Widget _dashButtonOutlined({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: Icon(icon, size: 20),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          foregroundColor: AppColors.primary,
          side: BorderSide(color: AppColors.primary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: onTap,
      ),
    );
  }
}
