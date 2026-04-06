import 'dart:async';
import 'dart:convert';
import 'package:bus_cargo_tracker/models/at_settings.dart';
import 'package:bus_cargo_tracker/models/twilio_settings.dart';
import 'package:bus_cargo_tracker/services/at_settings_service.dart';
import 'package:bus_cargo_tracker/services/twilio_settings_service.dart';
import 'package:bus_cargo_tracker/services/session_guard.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
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
  // Twilio settings adapter
  if (!Hive.isAdapterRegistered(TwilioSettingsAdapter().typeId)) {
    Hive.registerAdapter(TwilioSettingsAdapter());
  }

  await HiveService.openAllBoxes();
  await SyncService.ensureDeviceId();

  // API key injected via --dart-define and persisted to Hive on first run.
  const injectedKey = String.fromEnvironment('SYNC_API_KEY', defaultValue: '');
  if (injectedKey.isNotEmpty) {
    await SyncService.setApiKey(injectedKey);
  }

  // ── Seed admin BEFORE sync starts ─────────────────────────────────────────
  // Must run before AutoSyncService.start() to prevent a remote admin shell
  // from being pulled and causing hasAdmin=true with an empty password hash.
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

  // ── Fetch SMS config (AT + Twilio) BEFORE starting the app ────────────────
  // Awaited so credentials are ready before the first OTP is triggered.
  // Falls through silently if offline — OutboundQueueRunner retries every 20s.
  await _fetchAndStoreSmsConfig();

  // ── Start sync AFTER seed ──────────────────────────────────────────────────
  await AutoSyncService.instance.start();

  // Phase 5: sync immediately when connectivity is restored.
  Connectivity().onConnectivityChanged.listen((results) {
    final isOnline = results.any((r) => r != ConnectivityResult.none);
    if (isOnline) {
      AutoSyncService.instance.triggerNow();
    }
  });

  // F5: TTL checks on startup.
  await PropertyTtlService.runChecks();

  runApp(const MyApp());
}

/// Fetches AT + Twilio SMS configuration from the Cloudflare Worker /config
/// endpoint. Awaited on startup so both providers are ready before the first
/// sender registers and triggers an OTP SMS.
///
/// Smart routing in SmsService:
///   Uganda numbers (+256) → Africa's Talking (cheaper, local)
///   International numbers → Twilio (reliable global coverage)
///   If primary fails → fallback to other provider automatically
Future<void> _fetchAndStoreSmsConfig() async {
  try {
    final existingAt = AtSettingsService.getOrCreate();
    final existingTwilio = TwilioSettingsService.getOrCreate();

    final atConfigured = existingAt.apiKey.trim().isNotEmpty;
    final twilioConfigured = existingTwilio.isConfigured;

    // Both already configured — nothing to fetch
    if (atConfigured && twilioConfigured) return;

    if (!SyncService.hasApiKey()) return;
    final syncKey =
        (HiveService.appSettingsBox().get('syncApiKey') as String? ?? '')
            .trim();
    if (syncKey.isEmpty) return;

    final response = await http
        .get(
          Uri.parse('https://bus-cargo-sync.pserembae.workers.dev/config'),
          headers: {'X-Api-Key': syncKey},
        )
        .timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) return;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final sms = data['sms'] as Map<String, dynamic>?;
    if (sms == null) return;

    // ── Save AT credentials ────────────────────────────────────────────────
    if (!atConfigured) {
      final at = sms['at'] as Map<String, dynamic>?;
      if (at != null) {
        final apiKey = (at['apiKey'] as String? ?? '').trim();
        final username = (at['username'] as String? ?? '').trim();
        final senderId = (at['senderId'] as String? ?? '').trim();
        if (apiKey.isNotEmpty && username.isNotEmpty) {
          await AtSettingsService.save(
            AtSettings(
              apiKey: apiKey,
              username: username,
              senderId: senderId,
              isSandbox: false,
            ),
          );
        }
      }
    }

    // ── Save Twilio credentials ────────────────────────────────────────────
    if (!twilioConfigured) {
      final twilio = sms['twilio'] as Map<String, dynamic>?;
      if (twilio != null) {
        final accountSid = (twilio['accountSid'] as String? ?? '').trim();
        final authToken = (twilio['authToken'] as String? ?? '').trim();
        final from = (twilio['from'] as String? ?? '').trim();
        if (accountSid.isNotEmpty && authToken.isNotEmpty && from.isNotEmpty) {
          await TwilioSettingsService.save(
            TwilioSettings(
              accountSid: accountSid,
              authToken: authToken,
              from: from,
            ),
          );
        }
      }
    }
  } catch (_) {
    // Non-fatal — OutboundQueueRunner retries every 20s
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
      builder: (context, child) {
        return SessionGuard(child: child ?? const SizedBox.shrink());
      },
      home: SplashScreen(nextBuilder: RouteDeciderService.nextWidget),
    );
  }
}