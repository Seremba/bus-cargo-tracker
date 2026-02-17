import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/property.dart';

class PropertyLabelService {
  static String _fmt10(DateTime d) => d.toLocal().toString().substring(0, 10);

  static pw.Document buildLabelPdf(Property p) {
    final code = p.propertyCode.trim().isEmpty ? p.key.toString() : p.propertyCode.trim();

    final doc = pw.Document();

    // A6 label (good size for sticking on cargo)
    final pageFormat = PdfPageFormat.a6;

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(14),
        build: (_) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'BEBETO CARGO',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 8),

              pw.Text(
                'PROPERTY CODE',
                style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
              pw.Text(
                code,
                style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
              ),

              pw.SizedBox(height: 12),

              pw.Center(
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: code, // ✅ propertyCode QR (desk scanning)
                  width: 170,
                  height: 170,
                ),
              ),

              pw.SizedBox(height: 12),

              pw.Text('Receiver: ${p.receiverName}', style: const pw.TextStyle(fontSize: 11)),
              pw.Text('Phone: ${p.receiverPhone}', style: const pw.TextStyle(fontSize: 11)),
              pw.Text('Destination: ${p.destination}', style: const pw.TextStyle(fontSize: 11)),
              pw.Text('Items: ${p.itemCount}', style: const pw.TextStyle(fontSize: 11)),
              pw.SizedBox(height: 6),
              pw.Text('Created: ${_fmt10(p.createdAt)}', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            ],
          );
        },
      ),
    );

    return doc;
  }

  static Future<void> shareLabelPdf(Property p) async {
    final code = p.propertyCode.trim().isEmpty ? p.key.toString() : p.propertyCode.trim();
    final filename = 'label_$code.pdf';

    final doc = buildLabelPdf(p);
    final bytes = await doc.save();

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: filename)],
      text: 'Bebeto Cargo label: $code',
    );
  }
}
