import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';

import 'printer_settings_service.dart';

class PrinterService {
  PrinterService._();

  static final PrinterManager _pm = PrinterManager.instance;

  static Completer<void>? _printLock;

  static Future<T> _runWithPrintLock<T>(Future<T> Function() action) async {
    while (_printLock != null) {
      await _printLock!.future;
    }
    _printLock = Completer<void>();
    try {
      return await action();
    } finally {
      _printLock?.complete();
      _printLock = null;
    }
  }

  /// One-shot scan: yields a single list after timeout.
  static Stream<List<PrinterDevice>> scanBluetooth({
    Duration timeout = const Duration(seconds: 6),
    bool isBle = false,
  }) async* {
    final List<PrinterDevice> found = [];
    StreamSubscription<PrinterDevice>? sub;

    try {
      sub = _pm.discovery(type: PrinterType.bluetooth, isBle: isBle).listen(
        (device) {
          final addr = device.address;
          if (addr == null || addr.trim().isEmpty) return;

          final exists = found.any((d) => d.address == addr);
          if (!exists) found.add(device);
        },
        onError: (_) {},
        cancelOnError: false,
      );

      await Future.delayed(timeout);

      yield List<PrinterDevice>.unmodifiable(found);
    } finally {
      await sub?.cancel();
      // If plugin supports stopping discovery explicitly, call it here.
      // Some versions don't expose a stop method; canceling subscription is still helpful.
    }
  }

  static Future<bool> connectBluetooth(
    PrinterDevice device, {
    bool isBle = false,
    bool autoConnect = true,
  }) async {
    try {
      final addr = device.address;
      if (addr == null || addr.trim().isEmpty) return false;

      return await _pm.connect(
        type: PrinterType.bluetooth,
        model: BluetoothPrinterInput(
          name: device.name,
          address: addr.trim(),
          isBle: isBle,
          autoConnect: autoConnect,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  static Future<void> disconnectBluetooth() async {
    try {
      await _pm.disconnect(type: PrinterType.bluetooth);
    } catch (_) {}
  }

  /// Low-level send (expects connection exists).
  static Future<bool> printBytesBluetooth(Uint8List bytes) async {
    if (bytes.isEmpty) return false;

    return _runWithPrintLock(() async {
      try {
        return await _pm.send(type: PrinterType.bluetooth, bytes: bytes);
      } catch (_) {
        return false;
      }
    });
  }

  static Future<bool> ensureConnectedFromSaved({bool isBle = false}) async {
    try {
      final s = PrinterSettingsService.getOrCreate();
      final addr = (s.bluetoothAddress ?? '').trim();
      if (addr.isEmpty) return false;

      final name = (s.bluetoothName ?? '').trim();
      final safeName = name.isEmpty ? null : name;

      return await _pm.connect(
        type: PrinterType.bluetooth,
        model: BluetoothPrinterInput(
          name: safeName,
          address: addr,
          isBle: isBle,
          autoConnect: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  /// Recommended: print with auto-reconnect from saved settings.
  /// This keeps printing non-blocking at higher-level services:
  /// - if it fails, just returns false.
  static Future<bool> printBytesBluetoothSafe(
    Uint8List bytes, {
    bool isBle = false,
    bool tryReconnect = true,
  }) async {
    if (bytes.isEmpty) return false;

    return _runWithPrintLock(() async {
      try {
        // Try send first
        final ok = await _pm.send(type: PrinterType.bluetooth, bytes: bytes);
        if (ok) return true;

        if (!tryReconnect) return false;

        // Reconnect and retry once
        final re = await ensureConnectedFromSaved(isBle: isBle);
        if (!re) return false;

        return await _pm.send(type: PrinterType.bluetooth, bytes: bytes);
      } catch (_) {
        return false;
      }
    });
  }
}