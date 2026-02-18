import 'package:hive/hive.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PaymentExportService {
  static String fmt16(DateTime d) => d.toLocal().toString().substring(0, 16);

  static String csvEscape(String v) => '"${v.replaceAll('"', '""')}"';

  static String buildTodayCsv({
    required String stationLabel,
    required List todayItems,
    required Box propBox,
  }) {
    final b = StringBuffer();
    b.writeln(
      'station,createdAt,propertyCode,amount,currency,method,txnRef,recordedByUserId',
    );

    for (final x in todayItems) {
      final prop = propBox.get(int.tryParse(x.propertyKey));
      final code = (prop?.propertyCode.trim().isNotEmpty ?? false)
          ? prop!.propertyCode.trim()
          : '—';

      b.writeln([
        csvEscape(stationLabel),
        csvEscape(fmt16(x.createdAt)),
        csvEscape(code),
        csvEscape(x.amount.toString()),
        csvEscape(x.currency.trim().isEmpty ? 'UGX' : x.currency.trim()),
        csvEscape(x.method.trim().isEmpty ? '—' : x.method.trim()),
        csvEscape(x.txnRef.trim().isEmpty ? '—' : x.txnRef.trim()),
        csvEscape(
          x.recordedByUserId.trim().isEmpty ? '—' : x.recordedByUserId.trim(),
        ),
      ].join(','));
    }

    return b.toString();
  }

  static pw.Document buildTodayPdf({
    required String title,
    required String stationLabel,
    required DateTime todayStart,
    required List todayItems,
    required int todayTotal,
    required Box propBox,
  }) {
    final doc = pw.Document();

    pw.TableRow headerRow(List<String> cols) => pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: cols
              .map(
                (c) => pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text(
                    c,
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ),
              )
              .toList(),
        );

    pw.TableRow row(List<String> cols) => pw.TableRow(
          children: cols
              .map(
                (c) => pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text(c, maxLines: 2),
                ),
              )
              .toList(),
        );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (_) => [
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text('Station: $stationLabel'),
          pw.Text('Date: ${todayStart.toLocal().toString().substring(0, 10)}'),
          pw.SizedBox(height: 6),
          pw.Text('Today total: UGX $todayTotal • Payments: ${todayItems.length}'),
          pw.SizedBox(height: 12),
          if (todayItems.isEmpty)
            pw.Text('No payments today.')
          else
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.5),
              columnWidths: const {
                0: pw.FlexColumnWidth(2),
                1: pw.FlexColumnWidth(3),
                2: pw.FlexColumnWidth(2),
                3: pw.FlexColumnWidth(3),
              },
              children: [
                headerRow(['Time', 'Property', 'Amount', 'Method / TxnRef']),
                for (final x in todayItems)
                  row([
                    fmt16(x.createdAt),
                    () {
                      final prop = propBox.get(int.tryParse(x.propertyKey));
                      final code = (prop?.propertyCode.trim().isNotEmpty ?? false)
                          ? prop!.propertyCode.trim()
                          : '—';
                      return code;
                    }(),
                    '${x.currency.trim().isEmpty ? 'UGX' : x.currency.trim()} ${x.amount}',
                    '${x.method.trim().isEmpty ? '—' : x.method.trim()}\n'
                        '${x.txnRef.trim().isEmpty ? '—' : x.txnRef.trim()}',
                  ]),
              ],
            ),
        ],
      ),
    );

    return doc;
  }
}
