import 'dart:typed_data';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

import '../../models/payment_record.dart';
import '../../models/property.dart';

class EscPosReceiptBuilder {
  static Future<Uint8List> buildPaymentReceipt({
    required PaymentRecord pay,
    Property? property, // optional for code
    required int paperMm,
  }) async {
    final profile = await CapabilityProfile.load();
    final gen = Generator(
      paperMm >= 80 ? PaperSize.mm80 : PaperSize.mm58,
      profile,
    );

    final List<int> bytes = [];
    bytes.addAll(gen.reset());

    bytes.addAll(gen.text(
      'BEBETO CARGO',
      styles: const PosStyles(align: PosAlign.center, bold: true),
    ));
    bytes.addAll(gen.text(
      'PAYMENT RECEIPT',
      styles: const PosStyles(align: PosAlign.center, bold: true),
      linesAfter: 1,
    ));

    final propCode = (property?.propertyCode ?? '').trim();
    final shownCode = propCode.isNotEmpty ? propCode : (property?.key.toString() ?? pay.propertyKey);

    bytes.addAll(gen.text('Property: $shownCode'));
    bytes.addAll(gen.text('Station: ${pay.station.trim().isEmpty ? '—' : pay.station.trim()}'));
    bytes.addAll(gen.text('Time: ${pay.createdAt.toLocal().toString().substring(0, 16)}'));
    bytes.addAll(gen.hr());

    final curr = pay.currency.trim().isEmpty ? 'UGX' : pay.currency.trim();
    bytes.addAll(gen.text('Amount: $curr ${pay.amount}', styles: const PosStyles(bold: true)));
    bytes.addAll(gen.text('Method: ${pay.method.trim().isEmpty ? '—' : pay.method.trim()}'));
    bytes.addAll(gen.text('TxnRef: ${pay.txnRef.trim().isEmpty ? '—' : pay.txnRef.trim()}'));
    bytes.addAll(gen.text('RecordedBy: ${pay.recordedByUserId.trim().isEmpty ? '—' : pay.recordedByUserId.trim()}'));

    bytes.addAll(gen.feed(2));
    bytes.addAll(gen.text('Thank you', styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(gen.feed(1));
    bytes.addAll(gen.cut());

    return Uint8List.fromList(bytes);
  }
}
