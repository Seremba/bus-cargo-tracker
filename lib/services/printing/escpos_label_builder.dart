import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

import '../../models/property.dart';
import '../../models/property_item.dart';

class EscPosLabelBuilder {
  /// Existing label (property-level). Kept for backwards compatibility.
  static Future<Uint8List> buildPropertyLabel({
    required Property p,
    required int paperMm, // 58 or 80
  }) async {
    final profile = await CapabilityProfile.load();
    final gen = Generator(
      paperMm >= 80 ? PaperSize.mm80 : PaperSize.mm58,
      profile,
    );

    final List<int> bytes = [];
    bytes.addAll(gen.reset());

    // --- HEADER ---
    bytes.addAll(
      gen.text(
        'BEBETO CARGO',
        styles: const PosStyles(align: PosAlign.center, bold: true),
        linesAfter: 1,
      ),
    );

    // --- CODE BIG ---
    final code = (p.propertyCode).trim().isEmpty ? '${p.key}' : p.propertyCode.trim();
    bytes.addAll(
      gen.text(
        code,
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
        linesAfter: 1,
      ),
    );

    // --- QR (propertyCode) ---
    if (code.trim().isNotEmpty) {
      bytes.addAll(gen.qrcode(code, align: PosAlign.center));
      bytes.addAll(gen.feed(1));
    }

    // --- DETAILS ---
    bytes.addAll(gen.text('Receiver: ${_safe(p.receiverName)}'));
    bytes.addAll(gen.text('Phone: ${_safe(p.receiverPhone)}'));
    bytes.addAll(gen.text('Destination: ${_safe(p.destination)}'));
    bytes.addAll(gen.text('Items: ${p.itemCount}'));
    bytes.addAll(gen.feed(2));

    bytes.addAll(gen.cut());
    return Uint8List.fromList(bytes);
  }

  /// ✅ NEW: item-level label (one physical label per PropertyItem).
  static Future<Uint8List> buildItemLabel({
    required Property p,
    required PropertyItem item,
    required int paperMm, // 58 or 80
  }) async {
    final profile = await CapabilityProfile.load();
    final gen = Generator(
      paperMm >= 80 ? PaperSize.mm80 : PaperSize.mm58,
      profile,
    );

    final List<int> bytes = [];
    bytes.addAll(gen.reset());

    final propertyCode =
        p.propertyCode.trim().isEmpty ? '${p.key}' : p.propertyCode.trim();

    final tracking =
        p.trackingCode.trim().isEmpty ? '—' : p.trackingCode.trim();

    final itemLine = '${item.itemNo}/${p.itemCount}';

    // --- HEADER ---
    bytes.addAll(
      gen.text(
        'BEBETO CARGO',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      ),
    );

    // --- BIG ITEM NO ---
    bytes.addAll(
      gen.text(
        'ITEM $itemLine',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
        linesAfter: 1,
      ),
    );

    // --- QR (item.labelCode) ---
    final qr = item.labelCode.trim();
    if (qr.isNotEmpty) {
      bytes.addAll(gen.qrcode(qr, align: PosAlign.center));
      bytes.addAll(gen.feed(1));
    }

    // --- DETAILS ---
    bytes.addAll(gen.text('Property: $propertyCode'));
    bytes.addAll(gen.text('Tracking: $tracking'));
    bytes.addAll(gen.text('Receiver: ${_safe(p.receiverName)}'));
    bytes.addAll(gen.text('Phone: ${_safe(p.receiverPhone)}'));
    bytes.addAll(gen.text('Destination: ${_safe(p.destination)}'));

    bytes.addAll(gen.feed(2));
    bytes.addAll(gen.cut());

    return Uint8List.fromList(bytes);
  }

  static String _safe(String? v) {
    final s = (v ?? '').trim();
    return s.isEmpty ? '—' : s;
  }
}