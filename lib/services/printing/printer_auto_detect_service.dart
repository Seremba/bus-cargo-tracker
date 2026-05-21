import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

import '../../models/printer_settings.dart';

/// Detects the POS device brand at runtime and returns the appropriate
/// PrinterType. Add new brands here as new POS devices are deployed.
///
/// Supported brands:
/// - Urovo  (Q2I, Q2, i9000S, DT50 etc.)   → urovoInternal
/// - Sunmi  (T2, V2, P2, L2 etc.)           → sunmiInternal  [future]
/// - iMin   (D1, D3, M2 etc.)               → serialInternal [future]
/// - PAX    (A920, A80 etc.)                → serialInternal [future]
/// - Other  (generic Android phones/tablets) → bluetooth
class PrinterAutoDetectService {
  PrinterAutoDetectService._();

  static AndroidDeviceInfo? _cached;

  static Future<AndroidDeviceInfo> _info() async {
    _cached ??= await DeviceInfoPlugin().androidInfo;
    return _cached!;
  }

  /// Returns the best PrinterType for the current device.
  /// Called once on app startup and cached in PrinterSettings.
  static Future<PrinterType> detect() async {
    if (!Platform.isAndroid) return PrinterType.bluetooth;

    final info = await _info();
    final manufacturer = info.manufacturer.trim().toLowerCase();
    final model = info.model.trim().toLowerCase();
    final brand = info.brand.trim().toLowerCase();
    final fingerprint = info.fingerprint.trim().toLowerCase();

    // ── Urovo ──────────────────────────────────────────────────────────
    // Identifiers: manufacturer "urovo", or build fingerprint contains
    // "urovo", or model starts with known Urovo model prefixes.
    if (manufacturer.contains('urovo') ||
        brand.contains('urovo') ||
        fingerprint.contains('urovo') ||
        model.startsWith('q2') ||
        model.startsWith('i9') ||
        model.startsWith('dt') ||
        fingerprint.contains('pos-keys')) {
      return PrinterType.urovoInternal;
    }

    // ── Sunmi ───────────────────────────────────────────────────────────
    // Add sunmi_printer package when deploying Sunmi devices.
    if (manufacturer.contains('sunmi') ||
        brand.contains('sunmi') ||
        fingerprint.contains('sunmi')) {
      return PrinterType.sunmiInternal;
    }

    // ── iMin ────────────────────────────────────────────────────────────
    // Add imin_printer package when deploying iMin devices.
    if (manufacturer.contains('imin') ||
        brand.contains('imin') ||
        model.startsWith('d1') ||
        model.startsWith('d3')) {
      return PrinterType.serialInternal;
    }

    // ── PAX ─────────────────────────────────────────────────────────────
    if (manufacturer.contains('pax') ||
        brand.contains('pax') ||
        model.startsWith('a920') ||
        model.startsWith('a80')) {
      return PrinterType.serialInternal;
    }

    // ── Default — Bluetooth ─────────────────────────────────────────────
    return PrinterType.bluetooth;
  }

  /// Human-readable name for the detected printer type.
  static Future<String> detectedDeviceSummary() async {
    if (!Platform.isAndroid) return 'Non-Android device';
    final info = await _info();
    return '${info.manufacturer} ${info.model} (Android ${info.version.release})';
  }
}