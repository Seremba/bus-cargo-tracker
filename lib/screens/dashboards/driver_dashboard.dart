import 'package:flutter/material.dart';

import '../../services/session.dart';
import '../../widgets/logout_button.dart';
import 'driver_cargo_screen.dart';

class DriverDashboard extends StatelessWidget {
  const DriverDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final name = (Session.currentUserFullName ?? 'Driver').trim();

    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.60);

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Driver Dashboard'),
              Text(
                name.isEmpty ? '—' : name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: muted,
                ),
              ),
            ],
          ),
          actions: const [LogoutButton()],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SizedBox(height: 8),
            Text(
              'Welcome, $name',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Use “Manage Cargo” to view loaded items, active trips, and GPS checkpoint tracking.',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text('Manage Cargo'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DriverCargoScreen()),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}