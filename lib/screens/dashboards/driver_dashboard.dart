import 'package:bus_cargo_tracker/ui/app_colors.dart';
import 'package:flutter/material.dart';
import '../../services/session.dart';

import '../../widgets/logout_button.dart';
import 'driver_cargo_screen.dart';
import 'driver_manifest_screen.dart';

class DriverDashboard extends StatelessWidget {
  const DriverDashboard({super.key});

  // Initials avatar — Driver role color: green
  Widget _initialsAvatar(String fullName) {
    final parts = fullName.trim().split(' ');
    final initials = parts.length >= 2
        ? '${parts.first[0]}${parts.last[0]}'.toUpperCase()
        : fullName.isNotEmpty
            ? fullName.substring(0, fullName.length.clamp(0, 2)).toUpperCase()
            : 'DR';
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.green,
          fontWeight: FontWeight.bold,
          fontSize: 28,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = (Session.currentUserFullName ?? 'Driver').trim();
    final showName = name.isEmpty ? '—' : name;
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.60);

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                showName,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              // Role badge pill — Driver = green
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Driver',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.green,
                  ),
                ),
              ),
            ],
          ),
          actions: const [LogoutButton()],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
          children: [
            // ── Initials avatar centered ──
            Center(child: _initialsAvatar(showName)),
            const SizedBox(height: 16),

            // ── Welcome card ──
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: cs.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section title: 3px primary left border + icon + bold
                    Row(
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
                        Icon(Icons.waving_hand_outlined,
                            size: 17, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Welcome, $showName',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Use "Manage Cargo" to handle today\'s loading, start trips, and track GPS checkpoints.',
                      style: TextStyle(color: muted, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── Manage Cargo button ──
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.local_shipping_outlined, size: 20),
                label: const Text(
                  'Manage Cargo',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DriverCargoScreen(),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 14),

            // ── View Manifest button ──
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.list_alt_outlined, size: 20),
                label: const Text(
                  'View Cargo Manifest',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DriverManifestScreen(),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 14),

            // ── Tip row: icon + text (never plain text alone) ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline,
                    size: 14, color: muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'If you loaded only some items, start the trip and the receiver will see what departed vs what remained at station.',
                    style: TextStyle(
                        color: muted, fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}