import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/payment_record.dart';
import '../../models/property.dart';

/// Handles sharing payment receipts as plain text or PDF.
class ReceiptShareService {
  ReceiptShareService._();

  static String _s(String? v) => (v ?? '').trim();
  static String _fmt16(DateTime d) =>
      d.toLocal().toString().substring(0, 16);

  // ── Plain text ──────────────────────────────────────────────────────────

  static String buildTextReceipt({
    required PaymentRecord pay,
    required Property property,
  }) {
    final code = _s(property.propertyCode).isEmpty
        ? _s(pay.propertyKey)
        : property.propertyCode;
    final tracking = _s(property.trackingCode);
    final curr = _s(pay.currency).isEmpty ? 'UGX' : _s(pay.currency);
    final method = _s(pay.method).isEmpty ? '—' : _s(pay.method);
    final txnRef = _s(pay.txnRef).isEmpty ? '—' : _s(pay.txnRef);
    final station = _s(pay.station).isEmpty ? '—' : _s(pay.station);

    final buf = StringBuffer();
    buf.writeln('════════════════════════');
    buf.writeln('    UNEX LOGISTICS');
    buf.writeln('    PAYMENT RECEIPT');
    buf.writeln('════════════════════════');
    buf.writeln('Property : $code');
    if (tracking.isNotEmpty) buf.writeln('Tracking : $tracking');
    buf.writeln('Receiver : ${_s(property.receiverName)}');
    buf.writeln('Dest     : ${_s(property.destination)}');
    buf.writeln('Station  : $station');
    buf.writeln('Time     : ${_fmt16(pay.createdAt)}');
    buf.writeln('────────────────────────');
    buf.writeln('Amount   : $curr ${pay.amount}');
    buf.writeln('Method   : $method');
    buf.writeln('TxnRef   : $txnRef');
    buf.writeln('────────────────────────');
    buf.writeln('Help: +256 780 445860');
    buf.writeln('     +256 766 799490');
    buf.writeln('════════════════════════');
    buf.writeln('Thank you for using');
    buf.writeln('UNEx Logistics!');
    return buf.toString();
  }

  static Future<void> shareAsText({
    required PaymentRecord pay,
    required Property property,
  }) async {
    final text = buildTextReceipt(pay: pay, property: property);
    await Share.share(
      text,
      subject: 'UNEx Logistics Receipt — ${property.propertyCode}',
    );
  }

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

  // ── PDF ─────────────────────────────────────────────────────────────────

  static Future<void> shareAsPdf({
    required PaymentRecord pay,
    required Property property,
  }) async {
    final code = _s(property.propertyCode).isEmpty
        ? _s(pay.propertyKey)
        : property.propertyCode;
    final tracking = _s(property.trackingCode);
    final curr = _s(pay.currency).isEmpty ? 'UGX' : _s(pay.currency);
    final method = _s(pay.method).isEmpty ? '—' : _s(pay.method);
    final txnRef = _s(pay.txnRef).isEmpty ? '—' : _s(pay.txnRef);
    final station = _s(pay.station).isEmpty ? '—' : _s(pay.station);

    // Generate QR PNG for embedding
    final qrData = code.isNotEmpty
        ? code
        : tracking.isNotEmpty
            ? tracking
            : null;
    final qrPng =
        qrData != null ? await _generateQrPng(qrData) : null;

    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a6,
        margin: const pw.EdgeInsets.all(24),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Header
            pw.Center(
              child: pw.Text(
                'UNEX LOGISTICS',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Center(
              child: pw.Text(
                'PAYMENT RECEIPT',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Divider(),
            pw.SizedBox(height: 6),

            // Property details
            _pdfRow('Property', code),
            if (tracking.isNotEmpty) _pdfRow('Tracking', tracking),
            _pdfRow('Receiver', _s(property.receiverName)),
            _pdfRow('Destination', _s(property.destination)),
            _pdfRow('Station', station),
            _pdfRow('Date/Time', _fmt16(pay.createdAt)),
            pw.SizedBox(height: 6),
            pw.Divider(),
            pw.SizedBox(height: 6),

            // Payment details
            _pdfRow('Amount', '$curr ${pay.amount}', bold: true),
            _pdfRow('Method', method),
            _pdfRow('TxnRef', txnRef),
            pw.SizedBox(height: 6),
            pw.Divider(),
            pw.SizedBox(height: 8),

            // QR code
            if (qrPng != null) ...[
              pw.Center(
                child: pw.Text(
                  'Scan at pickup:',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Image(
                  pw.MemoryImage(qrPng),
                  width: 100,
                  height: 100,
                ),
              ),
              pw.SizedBox(height: 8),
            ],

            // Footer
            pw.Center(
              child: pw.Text(
                'Help: +256 780 445860  •  +256 766 799490',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(
                'Thank you for using UNEx Logistics!',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // Save to temp file and share
    final dir = await getTemporaryDirectory();
    final safeCode = code.replaceAll(RegExp(r'[^A-Za-z0-9\-]'), '_');
    final file = File('${dir.path}/receipt_$safeCode.pdf');
    await file.writeAsBytes(await doc.save());

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      subject: 'UNEx Logistics Receipt — $code',
    );
  }

  static pw.Widget _pdfRow(String label, String value,
      {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 80,
            child: pw.Text(
              label,
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value.isEmpty ? '—' : value,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight:
                    bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}