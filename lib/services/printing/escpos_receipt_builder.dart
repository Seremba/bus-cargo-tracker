import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

import '../../models/payment_record.dart';
import '../../models/property.dart';

class EscPosReceiptBuilder {
  EscPosReceiptBuilder._();

  static String _s(String? v) => (v ?? '').trim();

  static Future<Uint8List> buildPaymentReceipt({
    required PaymentRecord pay,
    Property? property, // optional for code + tracking
    required int paperMm,
  }) async {
    final profile = await CapabilityProfile.load();
    final gen = Generator(
      paperMm >= 80 ? PaperSize.mm80 : PaperSize.mm58,
      profile,
    );

    final List<int> bytes = [];

    bytes.addAll(gen.reset());

    // Header
    bytes.addAll(
      gen.text(
        'BEBETO CARGO',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      ),
    );
    bytes.addAll(
      gen.text(
        'PAYMENT RECEIPT',
        styles: const PosStyles(align: PosAlign.center, bold: true),
        linesAfter: 1,
      ),
    );

    // Property code
    final propCode = _s(property?.propertyCode);
    final shownCode = propCode.isNotEmpty
        ? propCode
        : (_s(property?.key?.toString()).isNotEmpty
              ? property!.key.toString()
              : _s(pay.propertyKey));

    bytes.addAll(gen.text('Property: $shownCode'));

    // Tracking code (NEW)
    final tracking = _s(property?.trackingCode);
    if (tracking.isNotEmpty) {
      bytes.addAll(
        gen.text('Tracking: $tracking', styles: const PosStyles(bold: true)),
      );
    }

    // Receiver updates (NEW — safe even if fields are missing at runtime)
    final notifyReceiver = (property?.notifyReceiver == true);
    if (notifyReceiver || tracking.isNotEmpty) {
      bytes.addAll(
        gen.text('Receiver updates: ${notifyReceiver ? "ON" : "OFF"}'),
      );
    }

    bytes.addAll(
      gen.text('Station: ${_s(pay.station).isEmpty ? '—' : _s(pay.station)}'),
    );
    bytes.addAll(
      gen.text('Time: ${pay.createdAt.toLocal().toString().substring(0, 16)}'),
    );

    bytes.addAll(gen.hr());

    // Payment details
    final curr = _s(pay.currency).isEmpty ? 'UGX' : _s(pay.currency);

    bytes.addAll(
      gen.text(
        'Amount: $curr ${pay.amount}',
        styles: const PosStyles(bold: true),
      ),
    );

    bytes.addAll(
      gen.text('Method: ${_s(pay.method).isEmpty ? '—' : _s(pay.method)}'),
    );
    bytes.addAll(
      gen.text('TxnRef: ${_s(pay.txnRef).isEmpty ? '—' : _s(pay.txnRef)}'),
    );
    bytes.addAll(
      gen.text(
        'RecordedBy: ${_s(pay.recordedByUserId).isEmpty ? '—' : _s(pay.recordedByUserId)}',
      ),
    );

    // Optional support/help line (NEW)
    bytes.addAll(gen.feed(1));
    bytes.addAll(
      gen.text(
        'Help: +256 780 445860 / +256 766 799490',
        styles: const PosStyles(align: PosAlign.center),
      ),
    );

    // Footer
    bytes.addAll(gen.feed(1));
    bytes.addAll(
      gen.text('Thank you', styles: const PosStyles(align: PosAlign.center)),
    );
    bytes.addAll(gen.feed(1));
    bytes.addAll(gen.cut());

    return Uint8List.fromList(bytes);
  }
}
