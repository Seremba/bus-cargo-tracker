import 'package:flutter/material.dart';
import '../../widgets/logout_button.dart';
import 'driver_cargo_screen.dart';

import '../../services/session.dart';

class DriverDashboard extends StatelessWidget {
  const DriverDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Driver Dashboard'),
              Text(
                (Session.currentUserFullName ?? '—').trim(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),

          actions: const [LogoutButton()],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Welcome, ${(Session.currentUserFullName ?? 'Driver').trim()}',
                style: const TextStyle(fontSize: 18),
              ),

              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const DriverCargoScreen(),
                      ),
                    );
                  },
                  child: const Text('Manage Cargo'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
