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
  String _stationFilter = '';
  DateTime _day = DateTime.now();

  String _fmt16(DateTime d) => d.toLocal().toString().substring(0, 16);

  DateTime get _dayStart => DateTime(_day.year, _day.month, _day.day);
  DateTime get _dayEnd =>
      DateTime(_day.year, _day.month, _day.day, 23, 59, 59, 999);

  String _csvEscape(String v) => '"${v.replaceAll('"', '""')}"';

  // Format numbers with commas e.g. 500000 → 500,000
  String _fmtAmount(int amount) {
    final abs = amount.abs();
    final str = abs.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buffer.write(',');
      buffer.write(str[i]);
    }
    return amount < 0 ? '-${buffer.toString()}' : buffer.toString();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _exportCsv(String filename, String csv) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(csv, flush: true);
    await Share.shareXFiles([
      XFile(file.path, mimeType: 'text/csv', name: filename),
    ]);
  }

  Future<void> _exportPdf(String filename, pw.Document doc) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(await doc.save(), flush: true);
    await Share.shareXFiles([
      XFile(file.path, mimeType: 'application/pdf', name: filename),
    ]);
  }

  bool _stationMatches(PaymentRecord x) {
    final f = _stationFilter.trim().toLowerCase();
    if (f.isEmpty) return true;
    return x.station.trim().toLowerCase() == f;
  }

  bool _dateMatches(PaymentRecord x) =>
      !x.createdAt.isBefore(_dayStart) && !x.createdAt.isAfter(_dayEnd);

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
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.55);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Payments'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Export',
            icon: const Icon(Icons.download_outlined),
            onSelected: (v) async {
              final all = payBox.values.toList();
              final filtered =
                  all
                      .where((x) => _stationMatches(x) && _dateMatches(x))
                      .toList()
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
                  b.writeln(
                    [
                      _csvEscape(stationLabel),
                      _csvEscape(_fmt16(x.createdAt)),
                      _csvEscape(_safeCode(prop)),
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
                      _csvEscape(x.note.trim().isEmpty ? '—' : x.note.trim()),
                    ].join(','),
                  );
                }
                await _exportCsv('payments_$slug.csv', b.toString());
                _snack('CSV exported ✅');
                return;
              }

              if (v == 'pdf') {
                final totalNet = filtered.fold<int>(0, (s, x) => s + x.amount);
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
                        'Collected: UGX $totalIn  •  Refunded: UGX $totalOut  •  Net: UGX $totalNet',
                      ),
                      pw.SizedBox(height: 12),
                      if (filtered.isEmpty)
                        pw.Text('No payments on this date.')
                      else
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
                            final prop = propBox.get(
                              int.tryParse(x.propertyKey),
                            );
                            final curr = x.currency.trim().isEmpty
                                ? 'UGX'
                                : x.currency.trim();
                            return [
                              _fmt16(x.createdAt),
                              _safeCode(prop),
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

          final stations =
              all
                  .map((x) => x.station.trim())
                  .where((s) => s.isNotEmpty)
                  .toSet()
                  .toList()
                ..sort();

          final filtered =
              all.where((x) => _stationMatches(x) && _dateMatches(x)).toList()
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          final totalNet = filtered.fold<int>(0, (sum, x) => sum + x.amount);
          final totalIn = filtered
              .where((x) => x.amount > 0)
              .fold<int>(0, (s, x) => s + x.amount);
          final totalOut = filtered
              .where((x) => x.amount < 0)
              .fold<int>(0, (s, x) => s + x.amount.abs());

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            children: [
              // ── Filters card ───────────────────────────────────────────
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Filters',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: muted,
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: _stationFilter.isEmpty ? '' : _stationFilter,
                        decoration: const InputDecoration(
                          labelText: 'Station',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.location_on_outlined),
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
                      // Date picker — uses theme primary color (orange)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: cs.primary,
                            side: BorderSide(
                              color: cs.primary.withValues(alpha: 0.50),
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 16,
                            ),
                          ),
                          icon: const Icon(Icons.calendar_today, size: 18),
                          label: Text(
                            'Date: ${_day.toLocal().toString().substring(0, 10)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _day,
                              firstDate: DateTime(2024, 1, 1),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
                            );
                            if (picked == null || !mounted) return;
                            setState(() => _day = picked);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // ── Totals card ────────────────────────────────────────────
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _stationFilter.trim().isEmpty
                            ? 'Totals — All stations'
                            : 'Totals — ${_stationFilter.trim()}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      _totalRow(
                        label: 'Collected',
                        value: 'UGX ${_fmtAmount(totalIn)}',
                        color: Colors.green.shade700,
                      ),
                      // Hide refunded row when zero
                      if (totalOut > 0) ...[
                        const SizedBox(height: 4),
                        _totalRow(
                          label: 'Refunded',
                          value: 'UGX ${_fmtAmount(totalOut)}',
                          color: Colors.red.shade600,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Divider(
                        height: 1,
                        color: cs.outlineVariant.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Net',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            'UGX ${_fmtAmount(totalNet)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${filtered.length} record${filtered.length == 1 ? '' : 's'}',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // ── Payment records ────────────────────────────────────────
              if (filtered.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      'No payments for this selection.',
                      style: TextStyle(color: muted),
                    ),
                  ),
                )
              else
                for (final x in filtered.take(80))
                  _paymentCard(context, x, propBox, cs, muted),
            ],
          );
        },
      ),
    );
  }

  Widget _totalRow({
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _paymentCard(
    BuildContext context,
    PaymentRecord x,
    Box<Property> propBox,
    ColorScheme cs,
    Color muted,
  ) {
    final prop = propBox.get(int.tryParse(x.propertyKey));
    final code = _safeCode(prop);
    final currency = x.currency.trim().isEmpty ? 'UGX' : x.currency.trim();
    final method = x.method.trim().isEmpty ? '—' : x.method.trim();
    final txnRef = x.txnRef.trim().isEmpty ? '—' : x.txnRef.trim();
    final station = x.station.trim().isEmpty ? '—' : x.station.trim();
    final note = x.note.trim();
    final isRefund = x.amount < 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Row 1: amount + kind + date ─────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Amount on its own line — no wrapping
                      Text(
                        '$currency ${_fmtAmount(x.amount)}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: isRefund ? Colors.red.shade600 : cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Kind + method on next line
                      Text(
                        '${x.kind}  •  $method',
                        style: TextStyle(fontSize: 13, color: muted),
                      ),
                    ],
                  ),
                ),
                // Date top-right
                Text(
                  _fmt16(x.createdAt),
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ),

            const SizedBox(height: 10),
            Divider(
              height: 1,
              color: cs.outlineVariant.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 8),

            // ── Row 2: property code ─────────────────────────────────────
            _detailRow(
              icon: Icons.inventory_2_outlined,
              text: 'Property: $code',
              muted: muted,
            ),
            const SizedBox(height: 4),

            // ── Row 3: station ───────────────────────────────────────────
            _detailRow(
              icon: Icons.location_on_outlined,
              text: 'Station: $station',
              muted: muted,
            ),
            const SizedBox(height: 4),

            // ── Row 4: txnRef ────────────────────────────────────────────
            _detailRow(
              icon: Icons.receipt_outlined,
              text: 'TxnRef: $txnRef',
              muted: muted,
            ),

            // ── Row 5: note (only if present) ────────────────────────────
            if (note.isNotEmpty) ...[
              const SizedBox(height: 4),
              _detailRow(
                icon: Icons.notes_outlined,
                text: 'Note: $note',
                muted: muted,
              ),
            ],

            const SizedBox(height: 10),

            // ── Adjust button — full width, clearly actionable ───────────
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.primary,
                  side: BorderSide(color: cs.primary.withValues(alpha: 0.40)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Adjust / Refund'),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AdminRefundAdjustmentScreen(payment: x),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _detailRow({
    required IconData icon,
    required String text,
    required Color muted,
  }) {
    return Row(
      children: [
        Icon(icon, size: 14, color: muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, color: muted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
