import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform.dart';

class PrinterService {
  PrinterService._();

  static final PrinterManager _pm = PrinterManager.instance;

  static Stream<List<PrinterDevice>> scanBluetooth({
    Duration timeout = const Duration(seconds: 6),
  }) async* {
    final List<PrinterDevice> found = [];
    StreamSubscription<PrinterDevice>? sub;

    try {
      sub = _pm.discovery(type: PrinterType.bluetooth).listen((device) {
        // Avoid duplicates
        final addr = device.address;
        if (addr == null) return;
        final exists = found.any((d) => d.address == addr);
        if (!exists) found.add(device);
      });

      await Future.delayed(timeout);
      yield found;
    } finally {
      await sub?.cancel();
    }
  }

  static Future<bool> connectBluetooth(PrinterDevice device) async {
    final addr = device.address;
    if (addr == null || addr.trim().isEmpty) return false;

    final res = await _pm.connect(
      type: PrinterType.bluetooth,
      model: BluetoothPrinterInput(
        name: device.name,
        address: addr,
        isBle: false, // ✅ classic bluetooth
        autoConnect: true,
      ),
    );

    return res;
  }

  static Future<void> disconnectBluetooth() async {
    await _pm.disconnect(type: PrinterType.bluetooth);
  }

  static Future<bool> printBytesBluetooth(Uint8List bytes) async {
    if (bytes.isEmpty) return false;
    return _pm.send(type: PrinterType.bluetooth, bytes: bytes);
  }
}
