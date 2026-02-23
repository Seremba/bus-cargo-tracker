import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'models/audit_event.dart';
import 'models/checkpoint.dart';
import 'models/notification_item.dart';
import 'models/printer_settings.dart';
import 'models/property.dart';
import 'models/property_status.dart';
import 'models/trip.dart';
import 'models/trip_status.dart';
import 'models/user.dart';
import 'models/user_role.dart';
import 'models/payment_record.dart';

import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/hive_service.dart';
import 'services/outbound_message_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  Hive.registerAdapter(PropertyAdapter());
  Hive.registerAdapter(PropertyStatusAdapter());
  Hive.registerAdapter(NotificationItemAdapter());
  Hive.registerAdapter(TripAdapter());
  Hive.registerAdapter(TripStatusAdapter());
  Hive.registerAdapter(CheckpointAdapter());
  Hive.registerAdapter(AuditEventAdapter());
  Hive.registerAdapter(UserAdapter());
  Hive.registerAdapter(UserRoleAdapter());
  Hive.registerAdapter(PaymentRecordAdapter());
  Hive.registerAdapter(PrinterSettingsAdapter());

  await HiveService.openAllBoxes();
  await OutboundMessageService.requeueOpenedMessages();
  // Prototype-friendly seeding; later keep only in debug/dev
  if (kDebugMode) {
    await AuthService.seedAdminIfMissing(
      phone: '0700000000',
      password: 'admin123',
      fullName: 'System Admin',
    );
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bus Property Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const LoginScreen(),
    );
  }
}
