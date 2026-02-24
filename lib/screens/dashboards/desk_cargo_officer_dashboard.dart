import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/user_role.dart';
import '../../services/hive_service.dart';
import '../../services/role_guard.dart';
import '../../services/session.dart';

import '../../services/exports/payment_export_service.dart';
import '../../services/file_share_service.dart';

import '../desk/desk_scan_and_pay_screen.dart';
import '../desk/desk_property_qr_scanner_screen.dart';
import '../desk/desk_property_details_screen.dart';
import '../common/outbound_messages_screen.dart';

class DeskCargoOfficerDashboard extends StatefulWidget {
  const DeskCargoOfficerDashboard({super.key});

  @override
  State<DeskCargoOfficerDashboard> createState() =>
      _DeskCargoOfficerDashboardState();
}

class _DeskCargoOfficerDashboardState extends State<DeskCargoOfficerDashboard> {
  bool _openingOutbound = false;

  String _fmt16(DateTime d) => d.toLocal().toString().substring(0, 16);

  Future<void> _openOutboundMessages() async {
    if (_openingOutbound) return;
    setState(() => _openingOutbound = true);

    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const OutboundMessagesScreen(),
        ),
      );
    } finally {
      if (mounted) setState(() => _openingOutbound = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!RoleGuard.hasAny({UserRole.deskCargoOfficer, UserRole.admin})) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    final payBox = HiveService.paymentBox();
    final propBox = HiveService.propertyBox();
    final name = (Session.currentUserFullName ?? '—').trim();
    final station = (Session.currentStationName ?? '').trim();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Desk Cargo Officer'),
              Text(
                station.isEmpty ? name : '$name • $station',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Scan'),
              Tab(text: 'Recent'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: _openingOutbound
                  ? 'Opening Outbound Messages...'
                  : 'Outbound Messages',
              icon: Icon(_openingOutbound ? Icons.hourglass_top : Icons.send_outlined),
              onPressed: _openingOutbound ? null : _openOutboundMessages,
            ),
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
                  final csv = PaymentExportService.buildTodayCsv(
                    stationLabel: stationLabel,
                    todayItems: todayItems,
                    propBox: propBox,
                  );

                  try {
                    final file = await FileShareService.writeTempText(
                      filename: 'payments_today_$slug.csv',
                      text: csv,
                    );
                    await FileShareService.shareFile(
                      file: file,
                      filename: 'payments_today_$slug.csv',
                      mimeType: 'text/csv',
                      text: 'Payments export: payments_today_$slug.csv',
                    );
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('CSV ready ✅ (payments_today_$slug.csv)'),
                      ),
                    );
                  } catch (e) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('CSV export failed: $e')),
                    );
                  }
                  return;
                }

                if (v == 'pdf_today') {
                  final doc = PaymentExportService.buildTodayPdf(
                    title: 'Payments Report (Today)',
                    stationLabel: stationLabel,
                    todayStart: todayStart,
                    todayItems: todayItems,
                    todayTotal: todayTotal,
                    propBox: propBox,
                  );

                  try {
                    final bytes = await doc.save();
                    final file = await FileShareService.writeTempBytes(
                      filename: 'payments_today_$slug.pdf',
                      bytes: bytes,
                    );
                    await FileShareService.shareFile(
                      file: file,
                      filename: 'payments_today_$slug.pdf',
                      mimeType: 'application/pdf',
                      text: 'Payments export: payments_today_$slug.pdf',
                    );
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('PDF ready ✅ (payments_today_$slug.pdf)'),
                      ),
                    );
                  } catch (e) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('PDF export failed: $e')),
                    );
                  }
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
            // TAB 1: Scan
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

            // TAB 2: Recent
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