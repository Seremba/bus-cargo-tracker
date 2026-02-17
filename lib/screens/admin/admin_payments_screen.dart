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
import '../admin/admin_refund_adjustment_screen.dart';

class AdminPaymentsScreen extends StatefulWidget {
  const AdminPaymentsScreen({super.key});

  @override
  State<AdminPaymentsScreen> createState() => _AdminPaymentsScreenState();
}

class _AdminPaymentsScreenState extends State<AdminPaymentsScreen> {
  String _stationFilter = ''; // empty = all
  DateTime _day = DateTime.now();

  String _fmt16(DateTime d) => d.toLocal().toString().substring(0, 16);

  DateTime get _dayStart => DateTime(_day.year, _day.month, _day.day);
  DateTime get _dayEnd =>
      DateTime(_day.year, _day.month, _day.day, 23, 59, 59, 999);

  String _csvEscape(String v) => '"${v.replaceAll('"', '""')}"';

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<void> _exportCsv(String filename, String csv) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(csv, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv', name: filename)],
    );
  }

  Future<void> _exportPdf(String filename, pw.Document doc) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(await doc.save(), flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: filename)],
    );
  }

  bool _stationMatches(PaymentRecord x) {
    final f = _stationFilter.trim().toLowerCase();
    if (f.isEmpty) return true;
    return x.station.trim().toLowerCase() == f;
  }

  bool _dateMatches(PaymentRecord x) {
    return !x.createdAt.isBefore(_dayStart) && !x.createdAt.isAfter(_dayEnd);
  }

  String _safeCode(Property? prop) {
    final code = (prop?.propertyCode ?? '').trim();
    return code.isEmpty ? '—' : code;
  }

  @override
  Widget build(BuildContext context) {
    if (!RoleGuard.hasRole(UserRole.admin)) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    final payBox = HiveService.paymentBox();
    final propBox = HiveService.propertyBox();

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Payments (Admin)'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Export',
            icon: const Icon(Icons.download_outlined),
            onSelected: (v) async {
              final all = payBox.values.toList();

              final filtered = all.where((x) {
                final stationOk = _stationMatches(x);
                final dateOk = _dateMatches(x);
                return stationOk && dateOk;
              }).toList()
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

              final stationLabel = _stationFilter.trim().isEmpty
                  ? 'All stations'
                  : _stationFilter.trim();

              final y = _day.year.toString().padLeft(4, '0');
              final m = _day.month.toString().padLeft(2, '0');
              final d = _day.day.toString().padLeft(2, '0');
              final slug = '$y$m$d';

              if (v == 'csv') {
                final b = StringBuffer();
                b.writeln(
                  'station,createdAt,propertyCode,kind,amount,currency,method,txnRef,note',
                );

                for (final x in filtered) {
                  final prop = propBox.get(int.tryParse(x.propertyKey));
                  final code = _safeCode(prop);

                  b.writeln([
                    _csvEscape(stationLabel),
                    _csvEscape(_fmt16(x.createdAt)),
                    _csvEscape(code),
                    _csvEscape(x.kind),
                    _csvEscape(x.amount.toString()),
                    _csvEscape(
                      x.currency.trim().isEmpty ? 'UGX' : x.currency.trim(),
                    ),
                    _csvEscape(
                      x.method.trim().isEmpty ? '—' : x.method.trim(),
                    ),
                    _csvEscape(
                      x.txnRef.trim().isEmpty ? '—' : x.txnRef.trim(),
                    ),
                    _csvEscape(
                      x.note.trim().isEmpty ? '—' : x.note.trim(),
                    ),
                  ].join(','));
                }

                await _exportCsv('payments_$slug.csv', b.toString());
                _snack('CSV exported ✅');
                return;
              }

              if (v == 'pdf') {
                final totalNet =
                    filtered.fold<int>(0, (sum, x) => sum + x.amount);
                final totalIn = filtered
                    .where((x) => x.amount > 0)
                    .fold<int>(0, (s, x) => s + x.amount);
                final totalOut = filtered
                    .where((x) => x.amount < 0)
                    .fold<int>(0, (s, x) => s + x.amount.abs());

                final doc = pw.Document();
                doc.addPage(
                  pw.MultiPage(
                    pageFormat: PdfPageFormat.a4,
                    build: (_) => [
                      pw.Text(
                        'Payments Report',
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text('Station: $stationLabel'),
                      pw.Text(
                        'Date: ${_day.toLocal().toString().substring(0, 10)}',
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        'Collected: UGX $totalIn • Refunded: UGX $totalOut • Net: UGX $totalNet',
                      ),
                      pw.SizedBox(height: 12),
                      if (filtered.isEmpty)
                        pw.Text('No payments on this date.')
                      else
                        // ✅ FIX: TableHelper.fromTextArray (no deprecation)
                        pw.TableHelper.fromTextArray(
                          headers: const [
                            'Time',
                            'Property',
                            'Kind',
                            'Amount',
                            'Method',
                            'TxnRef',
                          ],
                          data: filtered.take(120).map((x) {
                            final prop =
                                propBox.get(int.tryParse(x.propertyKey));
                            final code = _safeCode(prop);
                            final curr = x.currency.trim().isEmpty
                                ? 'UGX'
                                : x.currency.trim();
                            return [
                              _fmt16(x.createdAt),
                              code,
                              x.kind,
                              '$curr ${x.amount}',
                              x.method.trim().isEmpty ? '—' : x.method.trim(),
                              x.txnRef.trim().isEmpty ? '—' : x.txnRef.trim(),
                            ];
                          }).toList(),
                        ),
                    ],
                  ),
                );

                await _exportPdf('payments_$slug.pdf', doc);
                _snack('PDF exported ✅');
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'csv',
                child: Text('Export selected day (CSV)'),
              ),
              PopupMenuItem(
                value: 'pdf',
                child: Text('Export selected day (PDF)'),
              ),
            ],
          ),
        ],
      ),

      body: AnimatedBuilder(
        animation: Listenable.merge([
          payBox.listenable(),
          propBox.listenable(),
        ]),
        builder: (context, _) {
          final all = payBox.values.toList();

          final stations = all
              .map((x) => x.station.trim())
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList()
            ..sort();

          final filtered = all.where((x) {
            final stationOk = _stationMatches(x);
            final dateOk = _dateMatches(x);
            return stationOk && dateOk;
          }).toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          final totalNet =
              filtered.fold<int>(0, (sum, x) => sum + x.amount);
          final totalIn = filtered
              .where((x) => x.amount > 0)
              .fold<int>(0, (s, x) => s + x.amount);
          final totalOut = filtered
              .where((x) => x.amount < 0)
              .fold<int>(0, (s, x) => s + x.amount.abs());

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Filters',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: _stationFilter.isEmpty ? null : _stationFilter,
                        decoration: const InputDecoration(
                          labelText: 'Station (optional)',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('All stations'),
                          ),
                          ...stations.map(
                            (s) => DropdownMenuItem(value: s, child: Text(s)),
                          ),
                        ],
                        onChanged: (v) =>
                            setState(() => _stationFilter = (v ?? '').trim()),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today),
                        label: Text(
                          'Date: ${_day.toLocal().toString().substring(0, 10)}',
                        ),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _day,
                            firstDate: DateTime(2024, 1, 1),
                            lastDate:
                                DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked == null) return;
                          if (!mounted) return;
                          setState(() => _day = picked);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _stationFilter.trim().isEmpty
                            ? 'Totals (All stations)'
                            : 'Totals — ${_stationFilter.trim()}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text('Collected: UGX $totalIn'),
                      Text('Refunded: UGX $totalOut'),
                      const SizedBox(height: 6),
                      Text('Net: UGX $totalNet • Records: ${filtered.length}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (filtered.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('No payments for this selection.'),
                  ),
                )
              else
                for (final x in filtered.take(80))
                  Card(
                    child: ListTile(
                      title: Text(
                        'UGX ${x.amount} • ${x.kind} • ${x.method.trim().isEmpty ? '—' : x.method.trim()}',
                      ),
                      subtitle: () {
                        final prop = propBox.get(int.tryParse(x.propertyKey));
                        final code = _safeCode(prop);

                        final txn =
                            x.txnRef.trim().isEmpty ? '—' : x.txnRef.trim();
                        final note = x.note.trim().isEmpty
                            ? ''
                            : '\nNote: ${x.note.trim()}';

                        return Text(
                          'Property: $code\nStation: ${x.station.trim().isEmpty ? '—' : x.station.trim()}\nTxnRef: $txn$note',
                          style: const TextStyle(fontSize: 12),
                        );
                      }(),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _fmt16(x.createdAt),
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 6),
                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      AdminRefundAdjustmentScreen(payment: x),
                                ),
                              );
                            },
                            child: const Text('Adjust'),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}
