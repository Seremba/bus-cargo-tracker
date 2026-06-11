import '../../models/payment_record.dart';
import '../../models/printer_settings.dart';
import '../../models/property.dart';
import '../session.dart';
import 'escpos_receipt_builder.dart';
import 'printer_service.dart';
import 'printer_settings_service.dart';
import 'urovo_printer_service.dart';

class PaymentReceiptPrintService {
  PaymentReceiptPrintService._();

  static Future<bool?> printAfterPayment({
    required PaymentRecord record,
    required Property property,
  }) async {
    final settings = PrinterSettingsService.getOrCreate();
    final effective = await PrinterSettingsService.effectiveType();
    final partnerName = Session.currentPartnerName;

    // ── Urovo built-in printer ───────────────────────────────────────────
    if (effective == PrinterType.urovoInternal) {
      return UrovoPrinterService.printReceipt(
        pay: record,
        property: property,
        partnerName: partnerName,
      );
    }

    // ── Bluetooth printer ────────────────────────────────────────────────
    final savedAddr = (settings.bluetoothAddress ?? '').trim();
    if (savedAddr.isEmpty) return null;

    final bytes = await EscPosReceiptBuilder.buildPaymentReceipt(
      pay: record,
      property: property,
      paperMm: settings.paperMm,
      partnerName: partnerName,
    );

    return PrinterService.printBytesBluetoothSafe(
      bytes,
      tryReconnect: true,
    );
  }
}