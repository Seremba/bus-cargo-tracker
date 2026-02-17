import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/payment_record.dart';

class PaymentExportService {
  static String _csvEscape(String v) {
    final s = v.replaceAll('"', '""');
    return '"$s"';
  }

  static String paymentsCsv(List<PaymentRecord> items) {
    final b = StringBuffer();
    b.writeln([
      'paymentId',
      'propertyKey',
      'amount',
      'currency',
      'method',
      'txnRef',
      'station',
      'createdAt',
      'recordedByUserId',
    ].join(','));

    for (final r in items) {
      b.writeln([
        _csvEscape(r.paymentId),
        _csvEscape(r.propertyKey),
        _csvEscape(r.amount.toString()),
        _csvEscape(r.currency),
        _csvEscape(r.method),
        _csvEscape(r.txnRef),
        _csvEscape(r.station),
        _csvEscape(r.createdAt.toLocal().toString().substring(0, 19)),
        _csvEscape(r.recordedByUserId),
      ].join(','));
    }

    return b.toString();
  }

  static pw.Document paymentsPdf({
    required String title,
    required String station,
    required List<PaymentRecord> items,
  }) {
    final doc = pw.Document();

    pw.TableRow headerRow(List<String> cols) => pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
      children: cols.map((c) => pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text(c, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      )).toList(),
    );

    pw.TableRow row(List<String> cols) => pw.TableRow(
      children: cols.map((c) => pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text(c, maxLines: 2),
      )).toList(),
    );

    final total = items.fold<int>(0, (sum, r) => sum + r.amount);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (_) => [
          pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text('Station: $station'),
          pw.Text('Count: ${items.length}  •  Total: UGX $total'),
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(3),
              1: pw.FlexColumnWidth(2),
              2: pw.FlexColumnWidth(2),
              3: pw.FlexColumnWidth(3),
            },
            children: [
              headerRow(['Time', 'Amount', 'Method', 'PropertyKey']),
              for (final r in items)
                row([
                  r.createdAt.toLocal().toString().substring(0, 16),
                  '${r.currency} ${r.amount}',
                  r.method,
                  r.propertyKey,
                ]),
            ],
          ),
        ],
      ),
    );

    return doc;
  }

  static Future<void> exportCsv(String filename, String csv) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(csv, flush: true);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv', name: filename)],
      text: 'Payments export: $filename',
    );
  }

  static Future<void> exportPdf(String filename, pw.Document doc) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(await doc.save(), flush: true);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: filename)],
      text: 'Payments export: $filename',
    );
  }
}
