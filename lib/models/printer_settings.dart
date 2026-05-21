import 'package:hive/hive.dart';

part 'printer_settings.g.dart';

/// How the app connects to the receipt printer.
enum PrinterType {
  /// Auto-detected based on device brand — recommended default.
  auto,

  /// External Bluetooth thermal printer.
  bluetooth,

  /// Urovo Q2I / Q2 / i9000S built-in printer.
  urovoInternal,

  /// Sunmi T2/V2/P2 built-in printer — future.
  sunmiInternal,

  /// Generic Android POS via serial port — future.
  serialInternal,
}

@HiveType(typeId: 51)
class PrinterSettings extends HiveObject {
  @HiveField(0)
  String? bluetoothAddress;

  @HiveField(1)
  String? bluetoothName;

  @HiveField(2)
  int paperMm; // 58 or 80

  /// Serialised PrinterType name — defaults to 'auto'.
  @HiveField(3, defaultValue: 'auto')
  String printerTypeRaw;

  PrinterSettings({
    this.bluetoothAddress,
    this.bluetoothName,
    this.paperMm = 58,
    this.printerTypeRaw = 'auto',
  });

  PrinterType get printerType {
    switch (printerTypeRaw) {
      case 'bluetooth':
        return PrinterType.bluetooth;
      case 'urovoInternal':
        return PrinterType.urovoInternal;
      case 'sunmiInternal':
        return PrinterType.sunmiInternal;
      case 'serialInternal':
        return PrinterType.serialInternal;
      default:
        return PrinterType.auto;
    }
  }
}
