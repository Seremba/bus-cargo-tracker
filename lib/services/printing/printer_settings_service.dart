import 'package:hive/hive.dart';

import '../../models/printer_settings.dart';
import '../hive_service.dart';

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

  static void saveBluetooth({
    required String address,
    required String name,
    int paperMm = 58,
  }) {
    final Box box = HiveService.printerSettingsBox();
    box.put(
      _key,
      PrinterSettings(
        bluetoothAddress: address.trim(),
        bluetoothName: name.trim(),
        paperMm: paperMm,
      ),
    );
  }

  static void clear() {
    final Box box = HiveService.printerSettingsBox();
    box.delete(_key);
  }
}
