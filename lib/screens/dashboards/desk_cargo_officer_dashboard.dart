import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/payment_record.dart';
import '../../models/property.dart';
import '../../models/user_role.dart';
import '../../services/hive_service.dart';
import '../../services/role_guard.dart';
import '../../services/session.dart';

import '../desk/desk_scan_and_pay_screen.dart';
import '../desk/desk_property_qr_scanner_screen.dart';
import '../desk/desk_property_details_screen.dart';

class DeskCargoOfficerDashboard extends StatelessWidget {
  const DeskCargoOfficerDashboard({super.key});

  String _fmt16(DateTime d) => d.toLocal().toString().substring(0, 16);

  String _csvEscape(String v) => '"${v.replaceAll('"', '""')}"';

  Future<void> _exportCsv({
    required ScaffoldMessengerState messenger,
    required String filename,
    required String csv,
  }) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsString(csv, flush: true);

      await Share.shareXFiles([
        XFile(file.path, mimeType: 'text/csv', name: filename),
      ], text: 'Payments export: $filename');

      messenger.showSnackBar(
        SnackBar(content: Text('CSV ready ✅ ($filename)')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('CSV export failed: $e')));
    }
  }

  Future<void> _exportPdf({
    required ScaffoldMessengerState messenger,
    required String filename,
    required pw.Document doc,
  }) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$filename');

      await file.writeAsBytes(await doc.save(), flush: true);

      await Share.shareXFiles([
        XFile(file.path, mimeType: 'application/pdf', name: filename),
      ], text: 'Payments export: $filename');

      messenger.showSnackBar(
        SnackBar(content: Text('PDF ready ✅ ($filename)')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('PDF export failed: $e')));
    }
  }

  String _buildTodayCsv({
    required String stationLabel,
    required List<PaymentRecord> todayItems,
    required Box<Property> propBox,
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

      b.writeln(
        [
          _csvEscape(stationLabel),
          _csvEscape(_fmt16(x.createdAt)),
          _csvEscape(code),
          _csvEscape(x.amount.toString()),
          _csvEscape(x.currency.trim().isEmpty ? 'UGX' : x.currency.trim()),
          _csvEscape(x.method.trim().isEmpty ? '—' : x.method.trim()),
          _csvEscape(x.txnRef.trim().isEmpty ? '—' : x.txnRef.trim()),
          _csvEscape(
            x.recordedByUserId.trim().isEmpty ? '—' : x.recordedByUserId.trim(),
          ),
        ].join(','),
      );
    }

    return b.toString();
  }

  pw.Document _buildTodayPdf({
    required String title,
    required String stationLabel,
    required DateTime todayStart,
    required List<PaymentRecord> todayItems,
    required int todayTotal,
    required Box<Property> propBox,
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
          pw.Text(
            'Today total: UGX $todayTotal • Payments: ${todayItems.length}',
          ),
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
                    _fmt16(x.createdAt),
                    () {
                      final prop = propBox.get(int.tryParse(x.propertyKey));
                      final code =
                          (prop?.propertyCode.trim().isNotEmpty ?? false)
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

  @override
  Widget build(BuildContext context) {
    if (!RoleGuard.hasAny({UserRole.deskCargoOfficer, UserRole.admin})) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    final payBox = HiveService.paymentBox();
    final propBox = HiveService.propertyBox();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: const Text('Desk Cargo Officer'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Scan'),
              Tab(text: 'Recent'),
            ],
          ),
          actions: [
            PopupMenuButton<String>(
              tooltip: 'Export',
              icon: const Icon(Icons.download_outlined),
              onSelected: (v) async {
                // ✅ capture messenger BEFORE any await
                final messenger = ScaffoldMessenger.of(context);

                final station = (Session.currentStationName ?? '').trim();
                final stationLabel = station.isEmpty ? 'All stations' : station;

                final items = payBox.values.toList()
                  ..sort((a, c) => c.createdAt.compareTo(a.createdAt));

                final stationItems = station.isEmpty
                    ? items
                    : items
                          .where(
                            (x) =>
                                x.station.trim().toLowerCase() ==
                                station.toLowerCase(),
                          )
                          .toList();

                final now = DateTime.now();
                final todayStart = DateTime(now.year, now.month, now.day);

                final todayItems = stationItems
                    .where((x) => x.createdAt.isAfter(todayStart))
                    .toList();

                final todayTotal = todayItems.fold<int>(
                  0,
                  (sum, x) => sum + x.amount,
                );

                final y = now.year.toString().padLeft(4, '0');
                final m = now.month.toString().padLeft(2, '0');
                final d = now.day.toString().padLeft(2, '0');
                final slug = '$y$m$d';

                if (v == 'csv_today') {
                  final csv = _buildTodayCsv(
                    stationLabel: stationLabel,
                    todayItems: todayItems,
                    propBox: propBox,
                  );
                  await _exportCsv(
                    messenger: messenger,
                    filename: 'payments_today_$slug.csv',
                    csv: csv,
                  );
                  return;
                }

                if (v == 'pdf_today') {
                  final doc = _buildTodayPdf(
                    title: 'Payments Report (Today)',
                    stationLabel: stationLabel,
                    todayStart: todayStart,
                    todayItems: todayItems,
                    todayTotal: todayTotal,
                    propBox: propBox,
                  );
                  await _exportPdf(
                    messenger: messenger,
                    filename: 'payments_today_$slug.pdf',
                    doc: doc,
                  );
                  return;
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'csv_today',
                  child: Text('Export Today (CSV)'),
                ),
                PopupMenuItem(
                  value: 'pdf_today',
                  child: Text('Export Today (PDF)'),
                ),
              ],
            ),
          ],
        ),

        body: TabBarView(
          children: [
            // ✅ TAB 1: Scan (button + existing scan/pay UI)
            ListView(
              padding: const EdgeInsets.all(12),
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan Property QR (propertyCode)'),
                    onPressed: () async {
                      final raw = await Navigator.push<String?>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DeskPropertyQrScannerScreen(),
                        ),
                      );
                      if (raw == null || raw.trim().isEmpty) return;

                      if (!context.mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DeskPropertyDetailsScreen(
                            scannedCode: raw.trim(),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                const DeskScanAndPayScreen(),
              ],
            ),

            // ✅ TAB 2: Recent (AnimatedBuilder is correct)
            AnimatedBuilder(
              animation: Listenable.merge([
                payBox.listenable(),
                propBox.listenable(),
              ]),
              builder: (context, _) {
                final station = (Session.currentStationName ?? '').trim();

                final items = payBox.values.toList()
                  ..sort((a, c) => c.createdAt.compareTo(a.createdAt));

                final stationItems = station.isEmpty
                    ? items
                    : items
                          .where(
                            (x) =>
                                x.station.trim().toLowerCase() ==
                                station.toLowerCase(),
                          )
                          .toList();

                final now = DateTime.now();
                final todayStart = DateTime(now.year, now.month, now.day);

                final todayItems = stationItems
                    .where((x) => x.createdAt.isAfter(todayStart))
                    .toList();

                final todayTotal = todayItems.fold<int>(
                  0,
                  (sum, x) => sum + x.amount,
                );

                final allTotal = stationItems.fold<int>(
                  0,
                  (sum, x) => sum + x.amount,
                );

                if (stationItems.isEmpty) {
                  return ListView(
                    padding: const EdgeInsets.all(12),
                    children: const [
                      Card(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('No payments recorded yet.'),
                        ),
                      ),
                    ],
                  );
                }

                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              station.isEmpty
                                  ? 'Totals (All stations)'
                                  : 'Totals — $station',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Today: UGX $todayTotal  •  Payments: ${todayItems.length}',
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'All time: UGX $allTotal  •  Payments: ${stationItems.length}',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final x in stationItems.take(50))
                      Card(
                        child: ListTile(
                          title: Text(
                            'UGX ${x.amount} • ${x.method.trim().isEmpty ? '—' : x.method.trim()}',
                          ),
                          subtitle: () {
                            final prop = propBox.get(
                              int.tryParse(x.propertyKey),
                            );
                            final code =
                                (prop?.propertyCode.trim().isNotEmpty ?? false)
                                ? prop!.propertyCode.trim()
                                : '—';

                            return Text(
                              'Property: $code\nTxnRef: ${x.txnRef.trim().isEmpty ? '—' : x.txnRef.trim()}',
                              style: const TextStyle(fontSize: 12),
                            );
                          }(),
                          trailing: Text(
                            _fmt16(x.createdAt),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
