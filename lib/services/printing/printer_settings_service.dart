import 'package:hive/hive.dart';

import '../../models/printer_settings.dart';
import '../hive_service.dart';
import 'printer_auto_detect_service.dart';

class PrinterSettingsService {
  PrinterSettingsService._();

  static const String _key = 'settings';

  static PrinterSettings getOrCreate() {
    final Box box = HiveService.printerSettingsBox();
    final existing = box.get(_key) as PrinterSettings?;
    if (existing != null) return existing;

    final s = PrinterSettings();
    box.put(_key, s);
    return s;
  }

  /// Called once on app startup. If printer type is still 'auto' (default),
  /// detects the device brand and saves the appropriate type.
  static Future<void> initAutoDetect() async {
    final settings = getOrCreate();
    if (settings.printerType != PrinterType.auto) return;

    final detected = await PrinterAutoDetectService.detect();
    if (detected == PrinterType.auto) return;

    settings.printerTypeRaw = detected.name;
    await settings.save();
  }

  /// Returns the effective PrinterType — resolves 'auto' by detecting device.
  static Future<PrinterType> effectiveType() async {
    final settings = getOrCreate();
    if (settings.printerType != PrinterType.auto) {
      return settings.printerType;
    }
    return PrinterAutoDetectService.detect();
  }

  static Future<void> saveBluetooth({
    required String address,
    required String name,
    int paperMm = 58,
  }) async {
    final Box box = HiveService.printerSettingsBox();
    await box.put(
      _key,
      PrinterSettings(
        bluetoothAddress: address.trim(),
        bluetoothName: name.trim(),
        paperMm: paperMm,
        printerTypeRaw: 'bluetooth',
      ),
    );
  }

  static Future<void> saveUrovoInternal({int paperMm = 58}) async {
    final Box box = HiveService.printerSettingsBox();
    await box.put(
      _key,
      PrinterSettings(
        paperMm: paperMm,
        printerTypeRaw: 'urovoInternal',
      ),
    );
  }

  static Future<void> saveAutoDetect({int paperMm = 58}) async {
    final Box box = HiveService.printerSettingsBox();
    await box.put(
      _key,
      PrinterSettings(
        paperMm: paperMm,
        printerTypeRaw: 'auto',
      ),
    );
  }

  static Future<void> clear() async {
    final Box box = HiveService.printerSettingsBox();
    await box.delete(_key);
  }
}