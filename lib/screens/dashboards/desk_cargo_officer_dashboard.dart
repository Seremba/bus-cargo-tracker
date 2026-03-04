import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/outbound_message.dart';
import '../../models/user_role.dart';
import '../../services/exports/payment_export_service.dart';
import '../../services/file_share_service.dart';
import '../../services/hive_service.dart';
import '../../services/outbound_message_service.dart';
import '../../services/role_guard.dart';
import '../../services/session.dart';

import '../common/outbound_messages_screen.dart';
import '../desk/desk_property_details_screen.dart';
import '../desk/desk_property_qr_scanner_screen.dart';
import '../desk/desk_scan_and_pay_screen.dart';
import '../../widgets/logout_button.dart';

class DeskCargoOfficerDashboard extends StatefulWidget {
  const DeskCargoOfficerDashboard({super.key});

  @override
  State<DeskCargoOfficerDashboard> createState() =>
      _DeskCargoOfficerDashboardState();
}

class _DeskCargoOfficerDashboardState extends State<DeskCargoOfficerDashboard> {
  bool _openingOutbound = false;

  bool get _canUse =>
      RoleGuard.hasAny({UserRole.deskCargoOfficer, UserRole.admin});

  String _fmt16(DateTime d) => d.toLocal().toString().substring(0, 16);

  Future<void> _openOutboundMessagesSms() async {
    if (_openingOutbound) return;
    setState(() => _openingOutbound = true);
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const OutboundMessagesScreen(
            channelFilter: 'sms',
            title: 'SMS Processing',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _openingOutbound = false);
    }
  }

  Widget _badgePill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _smsBadge({required int queuedSms, required int failedSms}) {
    if (queuedSms <= 0 && failedSms <= 0) return const SizedBox.shrink();
    String fmt(int n) => n > 99 ? '99+' : n.toString();
    final text = '${fmt(queuedSms)}/${fmt(failedSms)}';

    return Positioned(right: 6, top: 6, child: _badgePill(text));
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_canUse) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    final payBox = HiveService.paymentBox();
    final propBox = HiveService.propertyBox();
    final outBox = HiveService.outboundMessageBox();

    final name = (Session.currentUserFullName ?? '—').trim();
    final station = (Session.currentStationName ?? '').trim();

    final headline = name.isEmpty ? 'Desk Cargo Officer' : name;
    final subtitle = station.isEmpty ? 'Desk Cargo Officer' : 'Desk • $station';

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                headline,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
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
            ValueListenableBuilder(
              valueListenable: outBox.listenable(),
              builder: (context, Box b, _) {
                int queuedSms = 0;
                int failedSms = 0;

                // Count only actionable SMS (attempts < maxAttempts)
                for (final m in b.values) {
                  if (m is! OutboundMessage) continue;
                  final ch = m.channel.trim().toLowerCase();
                  if (ch != 'sms') continue;

                  if (m.attempts >= OutboundMessageService.maxAttempts) {
                    continue;
                  }

                  final st = m.status.trim().toLowerCase();
                  if (st == OutboundMessageService.statusQueued) queuedSms++;
                  if (st == OutboundMessageService.statusFailed) failedSms++;
                }

                return Tooltip(
                  message: 'SMS — Queued: $queuedSms • Failed: $failedSms',
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      IconButton(
                        tooltip: _openingOutbound
                            ? 'Opening...'
                            : 'SMS Processing',
                        icon: const Icon(Icons.sms_outlined),
                        onPressed: _openingOutbound
                            ? null
                            : _openOutboundMessagesSms,
                      ),
                      _smsBadge(queuedSms: queuedSms, failedSms: failedSms),
                    ],
                  ),
                );
              },
            ),
            PopupMenuButton(
              tooltip: 'Export',
              icon: const Icon(Icons.download_outlined),
              onSelected: (v) async {
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

                final todayTotal = todayItems.fold(
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
            const LogoutButton(),
          ],
        ),
        body: TabBarView(
          children: [
            // TAB 1: Scan
            ListView(
              padding: const EdgeInsets.all(14),
              children: [
                _sectionTitle('Quick actions'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.qr_code_scanner),
                            label: const Text(
                              'Scan Property QR (propertyCode)',
                            ),
                            onPressed: () async {
                              final raw = await Navigator.push<String?>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const DeskPropertyQrScannerScreen(),
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
                        const SizedBox(height: 10),
                        Text(
                          'Tip: scan the printed property QR to open details quickly.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _sectionTitle('Register & receive payment'),
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

                final todayTotal = todayItems.fold(
                  0,
                  (sum, x) => sum + x.amount,
                );

                final allTotal = stationItems.fold(
                  0,
                  (sum, x) => sum + x.amount,
                );

                if (stationItems.isEmpty) {
                  return ListView(
                    padding: const EdgeInsets.all(14),
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
                  padding: const EdgeInsets.all(14),
                  children: [
                    _sectionTitle('Summary'),
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
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Today: UGX $todayTotal • Payments: ${todayItems.length}',
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'All time: UGX $allTotal • Payments: ${stationItems.length}',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _sectionTitle('Latest payments'),
                    for (final x in stationItems.take(50))
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.receipt_long),
                          title: Text(
                            'UGX ${x.amount} • ${x.method.trim().isEmpty ? '—' : x.method.trim()}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
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
