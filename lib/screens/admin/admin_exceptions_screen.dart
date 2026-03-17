import 'dart:io';

import 'package:bus_cargo_tracker/ui/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/user_role.dart';
import '../../services/exception_service.dart';
import '../../services/role_guard.dart';

class AdminExceptionsScreen extends StatefulWidget {
  const AdminExceptionsScreen({super.key});

  @override
  State<AdminExceptionsScreen> createState() => _AdminExceptionsScreenState();
}

class _AdminExceptionsScreenState extends State<AdminExceptionsScreen> {
  // 0=7d, 1=30d, 2=all
  int _rangeIndex = 1;

  DateTime? _startInclusive() {
    final now = DateTime.now();
    if (_rangeIndex == 0) return now.subtract(const Duration(days: 7));
    if (_rangeIndex == 1) return now.subtract(const Duration(days: 30));
    return null;
  }

  String _rangeLabel() {
    if (_rangeIndex == 0) return 'Last 7 days';
    if (_rangeIndex == 1) return 'Last 30 days';
    return 'All time';
  }

  String _rangeSlug() {
    if (_rangeIndex == 0) return '7d';
    if (_rangeIndex == 1) return '30d';
    return 'all';
  }

  String _s(String? v) => v ?? '';
  String _st(String? v) => (v ?? '').trim();

  String _csvEscape(String v) {
    final s = v.replaceAll('"', '""');
    return '"$s"';
  }

  String _fmt(DateTime? d) =>
      d == null ? '' : d.toLocal().toString().substring(0, 19);

  Future<void> _exportCsv(String filename, String csv) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsString(csv, flush: true);

      await Share.shareXFiles([
        XFile(file.path, mimeType: 'text/csv', name: filename),
      ], text: 'Exceptions export: $filename');

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('CSV ready ✅ ($filename)')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('CSV export failed: $e')));
    }
  }

  String _cargoCsv(List<CargoException> items, {required String type}) {
    final b = StringBuffer();
    b.writeln(
      [
        'type',
        'propertyKey',
        'receiverName',
        'receiverPhone',
        'destination',
        'status',
        'routeName',
        'createdAt',
        'inTransitAt',
        'deliveredAt',
        'pickedUpAt',
        'otpAttempts',
        'otpLockedUntil',
        'otpGeneratedAt',
        'tripId',
        'title',
        'subtitle',
      ].join(','),
    );
    for (final x in items) {
      final p = x.property;
      b.writeln(
        [
          _csvEscape(type),
          _csvEscape(p.key.toString()),
          _csvEscape(_s(p.receiverName)),
          _csvEscape(_s(p.receiverPhone)),
          _csvEscape(_s(p.destination)),
          _csvEscape(p.status.name),
          _csvEscape(_st(p.routeName)),
          _csvEscape(_fmt(p.createdAt)),
          _csvEscape(_fmt(p.inTransitAt)),
          _csvEscape(_fmt(p.deliveredAt)),
          _csvEscape(_fmt(p.pickedUpAt)),
          _csvEscape(p.otpAttempts.toString()),
          _csvEscape(_fmt(p.otpLockedUntil)),
          _csvEscape(_fmt(p.otpGeneratedAt)),
          _csvEscape(_st(p.tripId)),
          _csvEscape(x.title),
          _csvEscape(x.subtitle),
        ].join(','),
      );
    }
    return b.toString();
  }

  String _tripCsv(List<TripException> items, {required String type}) {
    final b = StringBuffer();
    b.writeln(
      [
        'type',
        'tripId',
        'routeId',
        'routeName',
        'driverUserId',
        'status',
        'startedAt',
        'endedAt',
        'lastCheckpointIndex',
        'title',
        'subtitle',
      ].join(','),
    );
    for (final x in items) {
      final t = x.trip;
      b.writeln(
        [
          _csvEscape(type),
          _csvEscape(_s(t.tripId)),
          _csvEscape(_st(t.routeId)),
          _csvEscape(_s(t.routeName)),
          _csvEscape(_s(t.driverUserId)),
          _csvEscape(t.status.name),
          _csvEscape(_fmt(t.startedAt)),
          _csvEscape(_fmt(t.endedAt)),
          _csvEscape(t.lastCheckpointIndex.toString()),
          _csvEscape(x.title),
          _csvEscape(x.subtitle),
        ].join(','),
      );
    }
    return b.toString();
  }

  Future<void> _exportPdf(String filename, pw.Document doc) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(await doc.save(), flush: true);

      await Share.shareXFiles([
        XFile(file.path, mimeType: 'application/pdf', name: filename),
      ], text: 'Exceptions export: $filename');

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('PDF ready ✅ ($filename)')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('PDF export failed: $e')));
    }
  }

  pw.Document _buildExceptionsPdf({
    required String title,
    required String rangeLabel,
    required List<CargoException> cargoItems,
    required List<TripException> tripItems,
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
          pw.Text('Range: $rangeLabel'),
          pw.SizedBox(height: 12),
          if (cargoItems.isNotEmpty) ...[
            pw.Text(
              'Cargo exceptions',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.5),
              columnWidths: const {
                0: pw.FlexColumnWidth(2),
                1: pw.FlexColumnWidth(2),
                2: pw.FlexColumnWidth(2),
                3: pw.FlexColumnWidth(4),
              },
              children: [
                headerRow(['Receiver', 'Phone', 'Station', 'Details']),
                for (final x in cargoItems)
                  row([
                    x.property.receiverName,
                    x.property.receiverPhone,
                    x.property.destination,
                    x.subtitle,
                  ]),
              ],
            ),
            pw.SizedBox(height: 14),
          ],
          if (tripItems.isNotEmpty) ...[
            pw.Text(
              'Trip exceptions',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.5),
              columnWidths: const {
                0: pw.FlexColumnWidth(3),
                1: pw.FlexColumnWidth(2),
                2: pw.FlexColumnWidth(5),
              },
              children: [
                headerRow(['Route', 'Driver', 'Details']),
                for (final x in tripItems)
                  row([x.trip.routeName, x.trip.driverUserId, x.subtitle]),
              ],
            ),
          ],
        ],
      ),
    );

    return doc;
  }

  @override
  Widget build(BuildContext context) {
    if (!RoleGuard.hasRole(UserRole.admin)) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    final cs = Theme.of(context).colorScheme;
    final start = _startInclusive();

    final locked = ExceptionService.lockedOtpCargo(startInclusive: start);
    final expired = ExceptionService.expiredOtpCargo(startInclusive: start);
    final pending = ExceptionService.stuckPending(startInclusive: start);
    final transit = ExceptionService.stuckInTransit(startInclusive: start);
    final notPicked = ExceptionService.deliveredNotPickedUp(
      startInclusive: start,
    );
    final stalled = ExceptionService.noProgressTrips(startInclusive: start);

    final otpTotal = locked.length + expired.length;
    final cargoTotal = pending.length + transit.length + notPicked.length;
    final tripsTotal = stalled.length;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          elevation: 2,
          title: const Text('Exceptions'),
          actions: [
            PopupMenuButton<String>(
              tooltip: 'Export',
              icon: const Icon(Icons.download_outlined),
              onSelected: (v) async {
                final slug = _rangeSlug();
                final range = _rangeLabel();

                if (v == 'otp_locked') {
                  await _exportCsv(
                    'exceptions_otp_locked_$slug.csv',
                    _cargoCsv(locked, type: 'otp_locked'),
                  );
                  return;
                }
                if (v == 'otp_expired') {
                  await _exportCsv(
                    'exceptions_otp_expired_$slug.csv',
                    _cargoCsv(expired, type: 'otp_expired'),
                  );
                  return;
                }
                if (v == 'cargo_pending') {
                  await _exportCsv(
                    'exceptions_stuck_pending_$slug.csv',
                    _cargoCsv(pending, type: 'stuck_pending'),
                  );
                  return;
                }
                if (v == 'cargo_transit') {
                  await _exportCsv(
                    'exceptions_stuck_in_transit_$slug.csv',
                    _cargoCsv(transit, type: 'stuck_in_transit'),
                  );
                  return;
                }
                if (v == 'cargo_notpicked') {
                  await _exportCsv(
                    'exceptions_delivered_not_picked_$slug.csv',
                    _cargoCsv(notPicked, type: 'delivered_not_picked'),
                  );
                  return;
                }
                if (v == 'trip_stalled') {
                  await _exportCsv(
                    'exceptions_trip_stalled_$slug.csv',
                    _tripCsv(stalled, type: 'trip_stalled'),
                  );
                  return;
                }
                if (v == 'pdf_all') {
                  final doc = _buildExceptionsPdf(
                    title: 'Exceptions (All)',
                    rangeLabel: range,
                    cargoItems: [
                      ...locked,
                      ...expired,
                      ...pending,
                      ...transit,
                      ...notPicked,
                    ],
                    tripItems: stalled,
                  );
                  await _exportPdf('exceptions_all_$slug.pdf', doc);
                  return;
                }
                if (v == 'pdf_otp') {
                  final doc = _buildExceptionsPdf(
                    title: 'Exceptions (OTP)',
                    rangeLabel: range,
                    cargoItems: [...locked, ...expired],
                    tripItems: const [],
                  );
                  await _exportPdf('exceptions_otp_$slug.pdf', doc);
                  return;
                }
                if (v == 'pdf_cargo') {
                  final doc = _buildExceptionsPdf(
                    title: 'Exceptions (Cargo)',
                    rangeLabel: range,
                    cargoItems: [...pending, ...transit, ...notPicked],
                    tripItems: const [],
                  );
                  await _exportPdf('exceptions_cargo_$slug.pdf', doc);
                  return;
                }
                if (v == 'pdf_trips') {
                  final doc = _buildExceptionsPdf(
                    title: 'Exceptions (Trips)',
                    rangeLabel: range,
                    cargoItems: const [],
                    tripItems: stalled,
                  );
                  await _exportPdf('exceptions_trips_$slug.pdf', doc);
                  return;
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'otp_locked',
                  child: Text('Export: Locked OTP (CSV)'),
                ),
                PopupMenuItem(
                  value: 'otp_expired',
                  child: Text('Export: Expired OTP (CSV)'),
                ),
                PopupMenuDivider(),
                PopupMenuItem(
                  value: 'cargo_pending',
                  child: Text('Export: Stuck Pending (CSV)'),
                ),
                PopupMenuItem(
                  value: 'cargo_transit',
                  child: Text('Export: Stuck In Transit (CSV)'),
                ),
                PopupMenuItem(
                  value: 'cargo_notpicked',
                  child: Text('Export: Delivered not Picked (CSV)'),
                ),
                PopupMenuDivider(),
                PopupMenuItem(
                  value: 'trip_stalled',
                  child: Text('Export: Stalled Trips (CSV)'),
                ),
                PopupMenuDivider(),
                PopupMenuItem(
                  value: 'pdf_all',
                  child: Text('Export: ALL (PDF)'),
                ),
                PopupMenuItem(
                  value: 'pdf_otp',
                  child: Text('Export: OTP (PDF)'),
                ),
                PopupMenuItem(
                  value: 'pdf_cargo',
                  child: Text('Export: Cargo (PDF)'),
                ),
                PopupMenuItem(
                  value: 'pdf_trips',
                  child: Text('Export: Trips (PDF)'),
                ),
              ],
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: 'OTP ($otpTotal)'),
              Tab(text: 'Cargo ($cargoTotal)'),
              Tab(text: 'Trips ($tripsTotal)'),
            ],
          ),
        ),
        body: Column(
          children: [
            // ── Range selector (inline pill chips, not dropdown) ──
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.30),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outlineVariant),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.date_range_outlined,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Range:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _rangePill(0, '7 days'),
                            const SizedBox(width: 6),
                            _rangePill(1, '30 days'),
                            const SizedBox(width: 6),
                            _rangePill(2, 'All time'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                children: [
                  _otpTab(locked: locked, expired: expired),
                  _cargoTab(
                    pending: pending,
                    transit: transit,
                    notPicked: notPicked,
                  ),
                  _tripTab(stalled: stalled),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Inline pill range selector ──
  Widget _rangePill(int index, String label) {
    final active = _rangeIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _rangeIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary
              : AppColors.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : AppColors.primary,
          ),
        ),
      ),
    );
  }

  Widget _otpTab({
    required List<CargoException> locked,
    required List<CargoException> expired,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        _sectionTitle(Icons.lock_outline, 'Locked OTP', locked.length),
        if (locked.isEmpty)
          _emptyState(
            Icons.lock_open_outlined,
            'No locked OTP cases in this range.',
          )
        else
          for (final x in locked) _cargoTile(x),
        const SizedBox(height: 16),
        _sectionTitle(Icons.timer_outlined, 'Expired OTP', expired.length),
        if (expired.isEmpty)
          _emptyState(
            Icons.hourglass_empty_outlined,
            'No expired OTP cases in this range.',
          )
        else
          for (final x in expired) _cargoTile(x),
      ],
    );
  }

  Widget _cargoTab({
    required List<CargoException> pending,
    required List<CargoException> transit,
    required List<CargoException> notPicked,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        _sectionTitle(
          Icons.hourglass_top_outlined,
          'Stuck Pending',
          pending.length,
        ),
        if (pending.isEmpty)
          _emptyState(
            Icons.check_circle_outline,
            'No stuck pending cargo in this range.',
          )
        else
          for (final x in pending) _cargoTile(x),
        const SizedBox(height: 16),
        _sectionTitle(
          Icons.local_shipping_outlined,
          'Stuck In Transit',
          transit.length,
        ),
        if (transit.isEmpty)
          _emptyState(
            Icons.check_circle_outline,
            'No stuck in-transit cargo in this range.',
          )
        else
          for (final x in transit) _cargoTile(x),
        const SizedBox(height: 16),
        _sectionTitle(
          Icons.inventory_2_outlined,
          'Delivered, Not Picked Up',
          notPicked.length,
        ),
        if (notPicked.isEmpty)
          _emptyState(
            Icons.check_circle_outline,
            'No delivered-not-picked cases in this range.',
          )
        else
          for (final x in notPicked) _cargoTile(x),
      ],
    );
  }

  Widget _tripTab({required List<TripException> stalled}) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        _sectionTitle(
          Icons.directions_bus_outlined,
          'Trips with No Progress',
          stalled.length,
        ),
        if (stalled.isEmpty)
          _emptyState(
            Icons.check_circle_outline,
            'No stalled trips in this range.',
          )
        else
          for (final x in stalled) _tripTile(x),
      ],
    );
  }

  Widget _cargoTile(CargoException x) {
    final p = x.property;
    final ts = (p.deliveredAt ?? p.createdAt).toLocal().toString().substring(
      0,
      16,
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Initials avatar
            _initialsAvatar(p.receiverName, _cargoAvatarColor(x)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    x.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    x.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  if (p.destination.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.place_outlined,
                          size: 12,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          p.destination,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _statusPill(p.status.name),
                const SizedBox(height: 6),
                Text(
                  ts,
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tripTile(TripException x) {
    final t = x.trip;
    final ts = t.startedAt.toLocal().toString().substring(0, 16);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Bus icon avatar
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.directions_bus_outlined,
                size: 20,
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    x.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    x.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  if (t.routeName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.route_outlined,
                          size: 12,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          t.routeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _statusPill(t.status.name),
                const SizedBox(height: 6),
                Text(
                  ts,
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Section title: 3px primary left border + icon + bold text + count badge
  Widget _sectionTitle(IconData icon, String text, int count) {
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
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: count > 0
                  ? AppColors.primary.withValues(alpha: 0.15)
                  : Colors.grey.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: count > 0 ? AppColors.primary : Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Empty state: icon + message row (never plain text alone)
  Widget _emptyState(IconData icon, String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.black38),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  /// Initials avatar: colored rounded square, 2-letter initials
  Widget _initialsAvatar(String fullName, Color color) {
    final parts = fullName.trim().split(' ');
    final initials = parts.length >= 2
        ? '${parts.first[0]}${parts.last[0]}'.toUpperCase()
        : fullName.isNotEmpty
        ? fullName.substring(0, fullName.length.clamp(0, 2)).toUpperCase()
        : '??';
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }

  /// Colored status pill chip (inline Container, not Flutter Chip)
  Widget _statusPill(String statusName) {
    final color = _statusColor(statusName);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        statusName,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Color _statusColor(String name) {
    switch (name.toLowerCase()) {
      case 'pending':
        return Colors.amber.shade700;
      case 'loaded':
        return AppColors.primary;
      case 'intransit':
      case 'in_transit':
        return Colors.blue;
      case 'delivered':
        return Colors.green;
      case 'pickedup':
      case 'picked_up':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  Color _cargoAvatarColor(CargoException x) {
    // Use a warm amber/orange for OTP exceptions, blue for others
    final title = x.title.toLowerCase();
    if (title.contains('lock') || title.contains('otp')) {
      return Colors.amber.shade700;
    }
    if (title.contains('transit')) return Colors.blue;
    if (title.contains('deliver')) return Colors.green;
    return AppColors.primary;
  }
}
