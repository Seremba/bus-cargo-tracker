import 'dart:typed_data';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';


import '../../models/property.dart';

class EscPosLabelBuilder {
  /// 58mm label (adhesive roll or receipt roll).
  static Future<Uint8List> buildPropertyLabel58(Property p) async {
    final profile = await CapabilityProfile.load();
    final gen = Generator(PaperSize.mm58, profile);

    final List<int> bytes = [];

    // Header
    bytes.addAll(gen.text(
      'BEBETO CARGO',
      styles: const PosStyles(align: PosAlign.center, bold: true),
      linesAfter: 1,
    ));

    // Big code
    bytes.addAll(gen.text(
      (p.propertyCode).trim().isEmpty ? '—' : p.propertyCode.trim(),
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
      linesAfter: 1,
    ));

    // Property QR (logistics QR) — encodes propertyCode (native ESC/POS QR)
    // (esc_pos_utils supports generator.qrcode('...')) :contentReference[oaicite:4]{index=4}
    final code = (p.propertyCode).trim();
    if (code.isNotEmpty) {
      bytes.addAll(gen.qrcode(code, align: PosAlign.center));
      bytes.addAll(gen.feed(1));
    }

    // Details (keep short for 58mm)
    bytes.addAll(gen.text('Receiver: ${_safe(p.receiverName)}'));
    bytes.addAll(gen.text('Destination: ${_safe(p.destination)}'));
    bytes.addAll(gen.text('Items: ${p.itemCount}'));

    // Optional timestamp
    // bytes.addAll(gen.text('Printed: ${DateTime.now().toLocal()}'));

    bytes.addAll(gen.feed(2));
    bytes.addAll(gen.cut());

    return Uint8List.fromList(bytes);
  }

  static String _safe(String? v) {
    final s = (v ?? '').trim();
    return s.isEmpty ? '—' : s;
  }
}
