import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:qr_flutter/qr_flutter.dart';
import 'package:urovo_print/urovo_print.dart';

import '../../models/payment_record.dart';
import '../../models/property.dart';

/// Handles receipt printing on the Urovo Q2I built-in 58mm printer.
/// Uses the Urovo Platform SDK via the urovo_print Flutter plugin.
class UrovoPrinterService {
  UrovoPrinterService._();

  static final UrovoPrint _printer = UrovoPrint();

  static const int _pageWidth = 384; // 58mm at 8 dots/mm

  static String _s(String? v) => (v ?? '').trim();
  static String _fmt16(DateTime d) =>
      d.toLocal().toString().substring(0, 16);

  // ── QR helper ────────────────────────────────────────────────────────────

  static Future<Uint8List?> _generateQrPng(String data,
      {double size = 200}) async {
    try {
      final painter = QrPainter(
        data: data,
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.H,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: ui.Color(0xFF000000),
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: ui.Color(0xFF000000),
        ),
      );
      final image = await painter.toImage(size);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  // ── Print receipt ────────────────────────────────────────────────────────

  /// Prints a payment receipt on the Urovo built-in printer.
  /// Returns true on success, false on failure.
  static Future<bool> printReceipt({
    required PaymentRecord pay,
    required Property property,
    String partnerName = '',
  }) async {
    try {
      final result = await _printer.open();
      if (result != 0) return false;

      final hasPartner = partnerName.trim().isNotEmpty;
      final code = _s(property.propertyCode).isEmpty
          ? _s(pay.propertyKey)
          : property.propertyCode;
      final tracking = _s(property.trackingCode);
      final curr =
          _s(pay.currency).isEmpty ? 'UGX' : _s(pay.currency);
      final method =
          _s(pay.method).isEmpty ? '—' : _s(pay.method);
      final txnRef =
          _s(pay.txnRef).isEmpty ? '—' : _s(pay.txnRef);
      final station =
          _s(pay.station).isEmpty ? '—' : _s(pay.station);

      // Setup page
      await _printer.setupPage(_pageWidth, -1);

      int y = 0;

      // ── Header ──────────────────────────────────────────────────
      if (hasPartner) {
        y = await _centeredBoldText(
            partnerName.trim().toUpperCase(), y, size: 32);
        y += 2;
        y = await _centeredText('Powered by UNEx Logistics', y, size: 20);
      } else {
        y = await _centeredBoldText('UNEX LOGISTICS', y, size: 32);
      }
      y += 4;
      y = await _centeredText('PAYMENT RECEIPT', y, size: 24);
      y += 8;
      y = await _divider(y);
      y += 8;

      // ── Property details ─────────────────────────────────────────
      y = await _labelValue('Property', code, y);
      if (tracking.isNotEmpty) {
        y = await _labelValue('Tracking', tracking, y);
      }
      y = await _labelValue('Receiver', _s(property.receiverName), y);
      y = await _labelValue('Destination', _s(property.destination), y);
      y = await _labelValue('Station', station, y);
      y = await _labelValue('Date/Time', _fmt16(pay.createdAt), y);
      y += 8;
      y = await _divider(y);
      y += 8;

      // ── Payment details ──────────────────────────────────────────
      y = await _labelValueBold(
          'Amount', '$curr ${pay.amount}', y, size: 28);
      y = await _labelValue('Method', method, y);
      y = await _labelValue('TxnRef', txnRef, y);
      y += 8;
      y = await _divider(y);
      y += 8;

      // ── QR code ──────────────────────────────────────────────────
      final qrData = code.isNotEmpty
          ? code
          : tracking.isNotEmpty
              ? tracking
              : null;
      if (qrData != null) {
        y = await _centeredText('Scan at pickup:', y, size: 20);
        y += 4;
        final qrPng = await _generateQrPng(qrData, size: 160);
        if (qrPng != null) {
          // Centre the QR: offset = (384 - 160) / 2 = 112
          await _printer.drawBitmap(qrPng, 112, y);
          y += 168;
        }
        y += 8;
      }

      // ── Footer ───────────────────────────────────────────────────
      y = await _centeredText(
          'Help: +256 780 445860  •  +256 766 799490', y,
          size: 18);
      y += 4;
      y = await _centeredBoldText('Thank you for using UNEx Logistics!',
          y, size: 20);
      y += 20;

      // Print and close
      await _printer.printPage(0);
      await _printer.setupPage(-1, -1);
      await _printer.clearPage();
      await _printer.close();

      return true;
    } catch (_) {
      try {
        await _printer.close();
      } catch (_) {}
      return false;
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static Future<int> _centeredText(String text, int y,
      {int size = 22}) async {
    await _printer.drawText(
      text,
      0,
      y,
      'simsun',
      size,
      false,
      false,
      1, // align center
    );
    return y + size + 4;
  }

  static Future<int> _centeredBoldText(String text, int y,
      {int size = 26}) async {
    await _printer.drawText(
      text,
      0,
      y,
      'simsun',
      size,
      true,
      false,
      1, // align center
    );
    return y + size + 4;
  }

  static Future<int> _labelValue(
      String label, String value, int y) async {
    final line = '$label: $value';
    await _printer.drawText(line, 0, y, 'simsun', 22, false, false, 0);
    return y + 26;
  }

  static Future<int> _labelValueBold(
      String label, String value, int y,
      {int size = 26}) async {
    final line = '$label: $value';
    await _printer.drawText(line, 0, y, 'simsun', size, true, false, 0);
    return y + size + 4;
  }

  static Future<int> _divider(int y) async {
    await _printer.drawLine(0, y, _pageWidth, y, 2);
    return y + 4;
  }

  // ── Test print ───────────────────────────────────────────────────────────

  static Future<bool> testPrint() async {
    try {
      final result = await _printer.open();
      if (result != 0) return false;

      await _printer.setupPage(_pageWidth, -1);
      int y = 0;
      y = await _centeredBoldText('UNEX LOGISTICS', y, size: 32);
      y += 8;
      y = await _centeredText('Printer test OK ✓', y, size: 24);
      y += 20;
      await _printer.printPage(0);
      await _printer.setupPage(-1, -1);
      await _printer.clearPage();
      await _printer.close();
      return true;
    } catch (_) {
      try {
        await _printer.close();
      } catch (_) {}
      return false;
    }
  }
}