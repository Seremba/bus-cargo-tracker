import 'package:flutter/material.dart';

import '../../services/session.dart';
import '../../widgets/logout_button.dart';

import 'driver_cargo_screen.dart';

class DriverDashboard extends StatelessWidget {
  const DriverDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final name = (Session.currentUserFullName ?? 'Driver').trim();
    final showName = name.isEmpty ? '—' : name;

    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.60);

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
              Text(
                'Driver Dashboard',
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
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: scheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome, $showName',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Use “Manage Cargo” to handle today’s loading, start trips, and track GPS checkpoints.',
                      style: TextStyle(color: muted, height: 1.35),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text('Manage Cargo'),
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

            const SizedBox(height: 10),
            Text(
              'Tip: If you loaded only some items, start the trip and the receiver will see what departed vs what remained at station.',
              style: TextStyle(color: muted, fontSize: 12, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}
