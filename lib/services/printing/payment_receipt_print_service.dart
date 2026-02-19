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
    final connected = await PrinterService.ensureConnectedFromSaved();
    if (!connected) return null; // printer not set / not connectable

    final settings = PrinterSettingsService.getOrCreate();
    final bytes = await EscPosReceiptBuilder.buildPaymentReceipt(
      pay: record,
      property: property,
      paperMm: settings.paperMm,
    );
    return PrinterService.printBytesBluetooth(bytes); // true/false
  }
}
