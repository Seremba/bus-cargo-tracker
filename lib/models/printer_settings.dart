import 'package:hive/hive.dart';

part 'printer_settings.g.dart';

@HiveType(typeId: 51)
class PrinterSettings extends HiveObject {
  @HiveField(0)
  String? bluetoothAddress;

  @HiveField(1)
  String? bluetoothName;

  @HiveField(2)
  int paperMm; // 58 or 80

  PrinterSettings({
    this.bluetoothAddress,
    this.bluetoothName,
    this.paperMm = 58,
  });
}
