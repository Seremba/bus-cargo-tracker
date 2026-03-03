import 'package:flutter/material.dart';

import '../models/user_role.dart';
import '../screens/login_screen.dart';
import '../screens/dashboards/admin_dashboard.dart';
import '../screens/dashboards/desk_cargo_officer_dashboard.dart';
import '../screens/dashboards/driver_dashboard.dart';

import '../screens/dashboards/staff_dashboard.dart';
import '../screens/sender/sender_dashboard.dart';
import 'session_service.dart';

class RouteDeciderService {
  static Future<Widget> nextWidget() async {
    final user = await SessionService.restore();
    if (user == null) return const LoginScreen();

    switch (user.role) {
      case UserRole.sender:
        return const SenderDashboard();
      case UserRole.staff:
        return const StaffDashboard();
      case UserRole.driver:
        return const DriverDashboard();
      case UserRole.admin:
        return const AdminDashboard();
      case UserRole.deskCargoOfficer:
        return const DeskCargoOfficerDashboard();
    }
  }
}
