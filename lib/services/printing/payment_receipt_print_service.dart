import '../../models/payment_record.dart';
import '../../models/printer_settings.dart';
import '../../models/property.dart';
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

    // ── Urovo built-in printer ───────────────────────────────────────────
    if (effective == PrinterType.urovoInternal) {
      return UrovoPrinterService.printReceipt(
        pay: record,
        property: property,
      );
    }

    // ── Sunmi built-in (future) ──────────────────────────────────────────
    // if (effective == PrinterType.sunmiInternal) {
    //   return SunmiPrinterService.printReceipt(pay: record, property: property);
    // }

    // ── Serial internal (future) ─────────────────────────────────────────
    // if (effective == PrinterType.serialInternal) {
    //   return SerialPrinterService.printReceipt(pay: record, property: property);
    // }

    // ── Bluetooth printer ────────────────────────────────────────────────
    final savedAddr = (settings.bluetoothAddress ?? '').trim();
    if (savedAddr.isEmpty) return null; // not configured

    final bytes = await EscPosReceiptBuilder.buildPaymentReceipt(
      pay: record,
      property: property,
      paperMm: settings.paperMm,
    );

    return PrinterService.printBytesBluetoothSafe(
      bytes,
      tryReconnect: true,
    );
  }
}