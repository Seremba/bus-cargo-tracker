import '../../models/payment_record.dart';
import '../../models/property.dart';
import 'escpos_receipt_builder.dart';
import 'printer_service.dart';
import 'printer_settings_service.dart';

class PaymentReceiptPrintService {
  PaymentReceiptPrintService._();

  static Future<bool?> printAfterPayment({
    required PaymentRecord record,
    required Property property,
  }) async {
    final settings = PrinterSettingsService.getOrCreate();
    final savedAddr = (settings.bluetoothAddress ?? '').trim();
    if (savedAddr.isEmpty) return null;

    final bytes = await EscPosReceiptBuilder.buildPaymentReceipt(
      pay: record,
      property: property,
      paperMm: settings.paperMm,
    );

    final ok = await PrinterService.printBytesBluetoothSafe(
      bytes,
      tryReconnect: true,
    );

    return ok; // true/false
  }
}
