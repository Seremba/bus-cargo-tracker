import 'dart:async';
import 'dart:convert';
import 'package:bus_cargo_tracker/models/at_settings.dart';
import 'package:bus_cargo_tracker/services/at_settings_service.dart';
import 'package:bus_cargo_tracker/services/session_guard.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;

import 'models/audit_event.dart';
import 'models/checkpoint.dart';
import 'models/notification_item.dart';
import 'models/outbound_message.dart';
import 'models/payment_record.dart';
import 'models/printer_settings.dart';
import 'models/property.dart';
import 'models/property_status.dart';
import 'models/trip.dart';
import 'models/trip_status.dart';
import 'models/user.dart';
import 'models/user_role.dart';
import 'models/sync_event.dart';
import 'models/sync_event_type.dart';

import 'screens/splash/splash_screen.dart';

import 'services/auth_service.dart';
import 'services/auto_sync_service.dart';
import 'services/hive_service.dart';
import 'services/property_ttl_service.dart';
import 'services/route_decider_service.dart';
import 'services/sync_service.dart';
import 'ui/app_colors.dart';

import 'models/property_item.dart';
import 'models/property_item_status.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  // Register adapters
  if (!Hive.isAdapterRegistered(PropertyAdapter().typeId)) {
    Hive.registerAdapter(PropertyAdapter());
  }
  if (!Hive.isAdapterRegistered(PropertyStatusAdapter().typeId)) {
    Hive.registerAdapter(PropertyStatusAdapter());
  }
  if (!Hive.isAdapterRegistered(PropertyItemAdapter().typeId)) {
    Hive.registerAdapter(PropertyItemAdapter());
  }
  if (!Hive.isAdapterRegistered(PropertyItemStatusAdapter().typeId)) {
    Hive.registerAdapter(PropertyItemStatusAdapter());
  }
  if (!Hive.isAdapterRegistered(NotificationItemAdapter().typeId)) {
    Hive.registerAdapter(NotificationItemAdapter());
  }
  if (!Hive.isAdapterRegistered(TripAdapter().typeId)) {
    Hive.registerAdapter(TripAdapter());
  }
  if (!Hive.isAdapterRegistered(TripStatusAdapter().typeId)) {
    Hive.registerAdapter(TripStatusAdapter());
  }
  if (!Hive.isAdapterRegistered(CheckpointAdapter().typeId)) {
    Hive.registerAdapter(CheckpointAdapter());
  }
  if (!Hive.isAdapterRegistered(AuditEventAdapter().typeId)) {
    Hive.registerAdapter(AuditEventAdapter());
  }
  if (!Hive.isAdapterRegistered(UserAdapter().typeId)) {
    Hive.registerAdapter(UserAdapter());
  }
  if (!Hive.isAdapterRegistered(UserRoleAdapter().typeId)) {
    Hive.registerAdapter(UserRoleAdapter());
  }
  if (!Hive.isAdapterRegistered(PaymentRecordAdapter().typeId)) {
    Hive.registerAdapter(PaymentRecordAdapter());
  }
  if (!Hive.isAdapterRegistered(PrinterSettingsAdapter().typeId)) {
    Hive.registerAdapter(PrinterSettingsAdapter());
  }
  if (!Hive.isAdapterRegistered(OutboundMessageAdapter().typeId)) {
    Hive.registerAdapter(OutboundMessageAdapter());
  }
  if (!Hive.isAdapterRegistered(SyncEventTypeAdapter().typeId)) {
    Hive.registerAdapter(SyncEventTypeAdapter());
  }
  if (!Hive.isAdapterRegistered(SyncEventAdapter().typeId)) {
    Hive.registerAdapter(SyncEventAdapter());
  }
  if (!Hive.isAdapterRegistered(AtSettingsAdapter().typeId)) {
    Hive.registerAdapter(AtSettingsAdapter());
  }

  await HiveService.openAllBoxes();

  await SyncService.ensureDeviceId();

  // API key is injected via --dart-define and persisted to Hive on first run.
  // Subsequent runs read the key from Hive automatically — no --dart-define needed.
  //
  // First run / key rotation:
  //   flutter run --dart-define=SYNC_API_KEY=your-key-here
  //
  // Release build:
  //   flutter build apk --dart-define=SYNC_API_KEY=your-key-here
  //
  // CI/CD: store key as a secret env variable and pass via --dart-define.
  // Future upgrade: move to flutter_secure_storage for per-device storage.
  const injectedKey = String.fromEnvironment('SYNC_API_KEY', defaultValue: '');
  if (injectedKey.isNotEmpty) {
    // New key provided — save to Hive, overwriting any previous key.
    await SyncService.setApiKey(injectedKey);
  }
  // If injectedKey is empty, SyncService uses whatever key is already
  // stored in Hive from the last time --dart-define was passed.

  await AutoSyncService.instance.start();

  // Phase 5: sync immediately when connectivity is restored.
  // This catches up events that were queued while the device was offline
  // without waiting for the next 5-minute ticker tick.
  Connectivity().onConnectivityChanged.listen((results) {
    final isOnline = results.any((r) => r != ConnectivityResult.none);
    if (isOnline) {
      AutoSyncService.instance.triggerNow();
    }
  });

  // F5: run TTL checks on every startup so expired/warned properties are
  // caught even if the app was closed for several days.
  // This is safe to call before the user logs in — it only reads/writes
  // Hive boxes, which are already open.
  await PropertyTtlService.runChecks();

  // Seed admin on first install if no admin exists.
  // Safe for production — only runs once when the user box has no admin.
  // Default credentials should be changed by the admin after first login.
  final hasAdmin = HiveService.userBox().values.any(
    (u) => u.role == UserRole.admin,
  );
  if (!hasAdmin) {
    await AuthService.seedAdminIfMissing(
      phone: '0700000000',
      password: 'admin123',
      fullName: 'System Admin',
    );
  }

  // Phase 8: Fetch AT SMS config from Cloudflare Worker on first install.
  // This avoids hardcoding or manually configuring AT credentials on every device.
  // Credentials are stored securely as Cloudflare environment secrets.
  // Only fetches if AT is not already configured in Hive.
  unawaited(_fetchAndStoreAtConfig());

  runApp(const MyApp());
}

/// Fetches AT SMS configuration from the Cloudflare Worker /config endpoint.
/// Called once on first install — credentials are persisted to Hive so
/// subsequent launches use the cached values without a network call.
/// If the fetch fails (offline, etc.) the app still works — SMS will be
/// queued and retried when credentials become available.
Future<void> _fetchAndStoreAtConfig() async {
  try {
    // Only fetch if AT not already configured
    final existing = AtSettingsService.getOrCreate();
    if (existing.apiKey.trim().isNotEmpty) return;

    // Use the public hasApiKey() check then read key via headers internally
    if (!SyncService.hasApiKey()) return;
    final syncKey = (HiveService.appSettingsBox().get('syncApiKey') as String? ?? '').trim();
    if (syncKey.isEmpty) return;

    final response = await http.get(
      Uri.parse('https://bus-cargo-sync.pserembae.workers.dev/config'),
      headers: {'X-Api-Key': syncKey},
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) return;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final sms = data['sms'] as Map<String, dynamic>?;
    if (sms == null) return;

    final apiKey = (sms['apiKey'] as String? ?? '').trim();
    final username = (sms['username'] as String? ?? '').trim();
    final senderId = (sms['senderId'] as String? ?? '').trim();

    if (apiKey.isEmpty || username.isEmpty) return;

    await AtSettingsService.save(AtSettings(
      apiKey: apiKey,
      username: username,
      senderId: senderId,
    ));

    debugPrint('[Config] AT SMS credentials fetched and stored.');
  } catch (e) {
    // Non-fatal — app works without SMS, messages stay queued
    debugPrint('[Config] Failed to fetch AT config: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  ThemeData _theme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.secondary,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.white,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        centerTitle: true,
        elevation: 1,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.secondary,
          side: BorderSide(color: AppColors.secondary.withValues(alpha: 0.5)),
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UNEx Logistics',
      debugShowCheckedModeBanner: false,
      theme: _theme(),
      // S5: SessionGuard wraps every screen built by the navigator.
      builder: (context, child) {
        return SessionGuard(child: child ?? const SizedBox.shrink());
      },
      home: SplashScreen(nextBuilder: RouteDeciderService.nextWidget),
    );
  }
}