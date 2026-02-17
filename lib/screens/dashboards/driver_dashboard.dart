import 'package:flutter/material.dart';
import '../../widgets/logout_button.dart';
import 'driver_cargo_screen.dart';

class DriverDashboard extends StatelessWidget {
  const DriverDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Driver Dashboard'),
          actions: const [LogoutButton()],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Welcome, Driver', style: TextStyle(fontSize: 18)),
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
