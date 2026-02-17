import 'dart:io';

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

  // =========================
  // Safe string helpers (no dynamic, no warnings)
  // =========================
  String _s(String? v) => v ?? '';
  String _st(String? v) => (v ?? '').trim();

  String _csvEscape(String v) {
    final s = v.replaceAll('"', '""');
    return '"$s"';
  }

  String _fmt(DateTime? d) =>
      d == null ? '' : d.toLocal().toString().substring(0, 19);

  // =========================
  // CSV helpers
  // =========================
  Future<void> _exportCsv(String filename, String csv) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsString(csv, flush: true);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv', name: filename)],
        text: 'Exceptions export: $filename',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV ready ✅ ($filename)')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV export failed: $e')),
      );
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

  // =========================
  // PDF helpers
  // =========================
  Future<void> _exportPdf(String filename, pw.Document doc) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$filename');

      await file.writeAsBytes(await doc.save(), flush: true);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf', name: filename)],
        text: 'Exceptions export: $filename',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF ready ✅ ($filename)')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF export failed: $e')),
      );
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

  // =========================
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {
    if (!RoleGuard.hasRole(UserRole.admin)) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    final start = _startInclusive();

    final locked = ExceptionService.lockedOtpCargo(startInclusive: start);
    final expired = ExceptionService.expiredOtpCargo(startInclusive: start);

    final pending = ExceptionService.stuckPending(startInclusive: start);
    final transit = ExceptionService.stuckInTransit(startInclusive: start);
    final notPicked =
        ExceptionService.deliveredNotPickedUp(startInclusive: start);

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

                // CSV
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

                // PDF
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
                PopupMenuItem(value: 'pdf_all', child: Text('Export: ALL (PDF)')),
                PopupMenuItem(value: 'pdf_otp', child: Text('Export: OTP (PDF)')),
                PopupMenuItem(value: 'pdf_cargo', child: Text('Export: Cargo (PDF)')),
                PopupMenuItem(value: 'pdf_trips', child: Text('Export: Trips (PDF)')),
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
            Padding(
              padding: const EdgeInsets.all(12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.date_range, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Range: ${_rangeLabel()}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      DropdownButton<int>(
                        value: _rangeIndex,
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('Last 7 days')),
                          DropdownMenuItem(value: 1, child: Text('Last 30 days')),
                          DropdownMenuItem(value: 2, child: Text('All time')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _rangeIndex = v);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
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

  // =========================
  // Tabs
  // =========================
  Widget _otpTab({
    required List<CargoException> locked,
    required List<CargoException> expired,
  }) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _sectionTitle('🔒 Locked OTP (${locked.length})'),
        if (locked.isEmpty) _emptyHint('No locked OTP cases in this range.'),
        for (final x in locked) _cargoTile(x),
        const SizedBox(height: 12),
        _sectionTitle('⏱ Expired OTP (${expired.length})'),
        if (expired.isEmpty) _emptyHint('No expired OTP cases in this range.'),
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
      padding: const EdgeInsets.all(12),
      children: [
        _sectionTitle('🟡 Stuck Pending (${pending.length})'),
        if (pending.isEmpty)
          _emptyHint('No stuck pending cargo in this range.'),
        for (final x in pending) _cargoTile(x),
        const SizedBox(height: 12),
        _sectionTitle('🔵 Stuck In Transit (${transit.length})'),
        if (transit.isEmpty)
          _emptyHint('No stuck in-transit cargo in this range.'),
        for (final x in transit) _cargoTile(x),
        const SizedBox(height: 12),
        _sectionTitle('🟢 Delivered but not picked up (${notPicked.length})'),
        if (notPicked.isEmpty)
          _emptyHint('No delivered-not-picked cases in this range.'),
        for (final x in notPicked) _cargoTile(x),
      ],
    );
  }

  Widget _tripTab({required List<TripException> stalled}) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _sectionTitle('🚍 Trips with no progress (${stalled.length})'),
        if (stalled.isEmpty) _emptyHint('No stalled trips in this range.'),
        for (final x in stalled) _tripTile(x),
      ],
    );
  }

  // =========================
  // Tiles
  // =========================
  Widget _cargoTile(CargoException x) {
    final p = x.property;
    return Card(
      child: ListTile(
        title: Text(x.title),
        subtitle: Text(x.subtitle),
        trailing: Text(
          (p.deliveredAt ?? p.createdAt).toLocal().toString().substring(0, 16),
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  Widget _tripTile(TripException x) {
    final t = x.trip;
    return Card(
      child: ListTile(
        title: Text(x.title),
        subtitle: Text(x.subtitle),
        trailing: Text(
          t.startedAt.toLocal().toString().substring(0, 16),
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  // =========================
  // Small UI helpers
  // =========================
  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
      );

  Widget _emptyHint(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text, style: const TextStyle(color: Colors.black54)),
      );
}
