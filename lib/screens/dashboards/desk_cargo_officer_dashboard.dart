import 'package:bus_cargo_tracker/ui/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/outbound_message.dart';
import '../../models/property.dart';
import '../../models/property_item_status.dart';
import '../../models/property_status.dart';
import '../../models/user_role.dart';
import '../../services/exports/payment_export_service.dart';
import '../../services/file_share_service.dart';
import '../../services/hive_service.dart';
import '../../services/outbound_message_service.dart';
import '../../services/property_item_service.dart';
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

  String _fmtAmount(int n) {
    final s = n.toString();
    final buffer = StringBuffer();
    final offset = s.length % 3;
    for (int i = 0; i < s.length; i++) {
      if (i != 0 && (i - offset) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }

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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _smsBadge({required int queuedSms, required int failedSms}) {
    if (queuedSms <= 0 && failedSms <= 0) return const SizedBox.shrink();
    String fmt(int n) => n > 99 ? '99+' : n.toString();
    return Positioned(
      right: 6,
      top: 6,
      child: _badgePill('${fmt(queuedSms)}/${fmt(failedSms)}'),
    );
  }

  Widget _sectionTitle(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 20,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Icon(icon, size: 17, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // Returns properties at this station that have at least one pending item
  // AND at least one already-loaded item — meaning a partial load happened
  // and the remainder needs to be loaded on the next trip.

  List<_PartialLoadEntry> _getPartiallyLoadedProperties(String station) {
    if (station.isEmpty) return [];

    final propBox = HiveService.propertyBox();
    final itemBox = HiveService.propertyItemBox();
    final itemSvc = PropertyItemService(itemBox);

    final entries = <_PartialLoadEntry>[];

    for (final p in propBox.values) {
      // Only pending/loaded status — inTransit means items already departed
      if (p.status != PropertyStatus.pending &&
          p.status != PropertyStatus.loaded) {
        continue;
      }

      // Only properties at this desk officer's station
      final loadedAt = (p.loadedAtStation).trim().toLowerCase();
      final currentStation = station.toLowerCase();
      if (loadedAt != currentStation) continue;

      final items = itemSvc.getItemsForProperty(p.key.toString());
      if (items.isEmpty) continue;

      final loadedCount = items
          .where(
            (x) =>
                x.status == PropertyItemStatus.loaded &&
                x.tripId.trim().isEmpty,
          )
          .length;

      final pendingCount = items
          .where((x) => x.status == PropertyItemStatus.pending)
          .length;

      // Only show if at least one item is loaded AND at least one is pending
      if (loadedCount > 0 && pendingCount > 0) {
        entries.add(
          _PartialLoadEntry(
            property: p,
            loadedCount: loadedCount,
            pendingCount: pendingCount,
            totalCount: items.length,
          ),
        );
      }
    }

    // Most recently loaded first
    entries.sort(
      (a, b) => (b.property.loadedAt ?? DateTime(0)).compareTo(
        a.property.loadedAt ?? DateTime(0),
      ),
    );

    return entries;
  }

  Widget _partialLoadCard(BuildContext context, _PartialLoadEntry entry) {
    final p = entry.property;
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.55);

    final code = p.propertyCode.trim().isEmpty
        ? p.key.toString()
        : p.propertyCode.trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  DeskPropertyDetailsScreen(scannedCode: p.propertyCode),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Amber avatar indicating partial state
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  size: 20,
                  color: Colors.amber,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Receiver name + code
                    Text(
                      p.receiverName.trim().isEmpty ? '—' : p.receiverName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      code,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                    const SizedBox(height: 6),
                    // Item progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: entry.loadedCount / entry.totalCount,
                        minHeight: 6,
                        backgroundColor: Colors.grey.withValues(alpha: 0.20),
                        valueColor: const AlwaysStoppedAnimation(Colors.amber),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${entry.loadedCount} loaded • '
                      '${entry.pendingCount} remaining',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.amber,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Partially Loaded pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Partial',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.amber,
                  ),
                ),
              ),
            ],
          ),
        ),
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

    final cs = Theme.of(context).colorScheme;

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
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange,
                  ),
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
                for (final m in b.values) {
                  if (m is! OutboundMessage) continue;
                  if (m.channel.trim().toLowerCase() != 'sms') continue;
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
                final st = (Session.currentStationName ?? '').trim();
                final stationLabel = st.isEmpty ? 'All stations' : st;

                final items = payBox.values.toList()
                  ..sort((a, c) => c.createdAt.compareTo(a.createdAt));
                final stationItems = st.isEmpty
                    ? items
                    : items
                          .where(
                            (x) =>
                                x.station.trim().toLowerCase() ==
                                st.toLowerCase(),
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

                final slug =
                    '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';

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
            // ── TAB 1: Scan ──
            AnimatedBuilder(
              animation: Listenable.merge([
                propBox.listenable(),
                HiveService.propertyItemBox().listenable(),
              ]),
              builder: (context, _) {
                final partials = _getPartiallyLoadedProperties(station);

                return ListView(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
                  children: [
                    if (partials.isNotEmpty) ...[
                      Row(
                        children: [
                          Container(
                            width: 3,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Colors.amber,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.pending_actions_outlined,
                            size: 17,
                            color: Colors.amber,
                          ),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: Text(
                              'Remaining items to load',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${partials.length}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.amber,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      for (final entry in partials)
                        _partialLoadCard(context, entry),
                      const SizedBox(height: 8),
                      const Divider(),
                      const SizedBox(height: 8),
                    ],

                    _sectionTitle(Icons.bolt_outlined, 'Quick actions'),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                icon: const Icon(
                                  Icons.qr_code_scanner_outlined,
                                  size: 20,
                                ),
                                label: const Text(
                                  'Scan Property QR (propertyCode)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                onPressed: () async {
                                  final raw = await Navigator.push<String?>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const DeskPropertyQrScannerScreen(),
                                    ),
                                  );
                                  if (raw == null || raw.trim().isEmpty) {
                                    return;
                                  }
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
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 14,
                                  color: cs.onSurface.withValues(alpha: 0.45),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Tip: scan the printed property QR to open details quickly.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: cs.onSurface.withValues(
                                        alpha: 0.60,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _sectionTitle(
                      Icons.point_of_sale_outlined,
                      'Register & receive payment',
                    ),
                    const DeskScanAndPayScreen(),
                  ],
                );
              },
            ),

            // ── TAB 2: Recent ──
            AnimatedBuilder(
              animation: Listenable.merge([
                payBox.listenable(),
                propBox.listenable(),
              ]),
              builder: (context, _) {
                final st = (Session.currentStationName ?? '').trim();

                final items = payBox.values.toList()
                  ..sort((a, c) => c.createdAt.compareTo(a.createdAt));

                final stationItems = st.isEmpty
                    ? items
                    : items
                          .where(
                            (x) =>
                                x.station.trim().toLowerCase() ==
                                st.toLowerCase(),
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
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.receipt_long_outlined,
                          size: 16,
                          color: Colors.black38,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'No payments recorded yet.',
                          style: TextStyle(color: Colors.black54, fontSize: 13),
                        ),
                      ],
                    ),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
                  children: [
                    _sectionTitle(Icons.bar_chart_outlined, 'Summary'),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              st.isEmpty
                                  ? 'Totals (All stations)'
                                  : 'Totals — $st',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _summaryRow(
                              icon: Icons.today_outlined,
                              label: 'Today',
                              amount: todayTotal,
                              count: todayItems.length,
                              color: AppColors.primary,
                            ),
                            const SizedBox(height: 6),
                            _summaryRow(
                              icon: Icons.history_outlined,
                              label: 'All time',
                              amount: allTotal,
                              count: stationItems.length,
                              color: Colors.blue,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _sectionTitle(
                      Icons.receipt_long_outlined,
                      'Latest payments',
                    ),
                    for (final x in stationItems.take(50))
                      _paymentTile(x, propBox),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow({
    required IconData icon,
    required String label,
    required int amount,
    required int count,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'UGX ${_fmtAmount(amount)}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(
              '$count payment${count == 1 ? '' : 's'}',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.50),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _paymentTile(dynamic x, dynamic propBox) {
    final prop = propBox.get(int.tryParse(x.propertyKey));
    final code = (prop?.propertyCode.trim().isNotEmpty ?? false)
        ? prop!.propertyCode.trim()
        : '—';
    final method = x.method.trim().isEmpty ? '—' : x.method.trim();
    final txnRef = x.txnRef.trim().isEmpty ? '—' : x.txnRef.trim();
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.55);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.receipt_long_outlined,
                size: 20,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'UGX ${_fmtAmount(x.amount)}  •  $method',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 12, color: muted),
                      const SizedBox(width: 3),
                      Text(
                        'Property: $code',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.tag_outlined, size: 12, color: muted),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          'Ref: $txnRef',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.access_time_outlined, size: 12, color: muted),
                      const SizedBox(width: 3),
                      Text(
                        _fmt16(x.createdAt),
                        style: TextStyle(fontSize: 11, color: muted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PartialLoadEntry {
  final Property property;
  final int loadedCount;
  final int pendingCount;
  final int totalCount;

  const _PartialLoadEntry({
    required this.property,
    required this.loadedCount,
    required this.pendingCount,
    required this.totalCount,
  });
}
