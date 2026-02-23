import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/outbound_message.dart';
import '../../models/user_role.dart';
import '../../services/hive_service.dart';
import '../../services/outbound_message_service.dart';
import '../../services/role_guard.dart';

class AdminOutboundMessagesScreen extends StatefulWidget {
  const AdminOutboundMessagesScreen({super.key});

  @override
  State<AdminOutboundMessagesScreen> createState() =>
      _AdminOutboundMessagesScreenState();
}

class _AdminOutboundMessagesScreenState extends State<AdminOutboundMessagesScreen> {
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

  String _fmt(DateTime? d) =>
      d == null ? '—' : d.toLocal().toString().substring(0, 16);

  String _csvEscape(String v) => '"${v.replaceAll('"', '""')}"';

  bool _inRange(OutboundMessage m, DateTime? startInclusive) {
    if (startInclusive == null) return true;
    return m.createdAt.isAfter(startInclusive) || m.createdAt.isAtSameMomentAs(startInclusive);
  }

  List<OutboundMessage> _filterByStatus(List<OutboundMessage> all, String status) {
    final s = status.trim().toLowerCase();
    return all.where((m) => m.status.trim().toLowerCase() == s).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> _exportCsv(String filename, String csv) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsString(csv, flush: true);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv', name: filename)],
        text: 'Outbound messages export: $filename',
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

  String _buildCsv(List<OutboundMessage> items, {required String rangeLabel}) {
    final b = StringBuffer();
    b.writeln(
      [
        'range',
        'id',
        'toPhone',
        'channel',
        'status',
        'attempts',
        'createdAt',
        'lastAttemptAt',
        'propertyKey',
        'body',
      ].join(','),
    );

    for (final m in items) {
      b.writeln(
        [
          _csvEscape(rangeLabel),
          _csvEscape(_s(m.id)),
          _csvEscape(_s(m.toPhone)),
          _csvEscape(_st(m.channel)),
          _csvEscape(_st(m.status)),
          _csvEscape(m.attempts.toString()),
          _csvEscape(_fmt(m.createdAt)),
          _csvEscape(_fmt(m.lastAttemptAt)),
          _csvEscape(_st(m.propertyKey)),
          _csvEscape(_s(m.body)),
        ].join(','),
      );
    }

    return b.toString();
  }

  Future<void> _openNext() async {
    final msg = await OutboundMessageService.processQueueOpenNext();
    if (!mounted) return;

    if (msg == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No queued messages ready to send.')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Opened ${msg.channel} for ${msg.toPhone} ✅')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!RoleGuard.hasRole(UserRole.admin)) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    final start = _startInclusive();
    final box = HiveService.outboundMessageBox();

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          elevation: 2,
          title: const Text('Outbound Messages'),
          actions: [
            IconButton(
              tooltip: 'Open next queued message',
              icon: const Icon(Icons.play_arrow_outlined),
              onPressed: _openNext,
            ),
            PopupMenuButton<String>(
              tooltip: 'Export',
              icon: const Icon(Icons.download_outlined),
              onSelected: (v) async {
                final slug = _rangeSlug();
                final range = _rangeLabel();

                final all = box.values
                    .where((m) => _inRange(m, start))
                    .toList();

                if (v == 'csv_all') {
                  await _exportCsv(
                    'outbound_messages_all_$slug.csv',
                    _buildCsv(all, rangeLabel: range),
                  );
                  return;
                }
                if (v == 'csv_queued') {
                  await _exportCsv(
                    'outbound_messages_queued_$slug.csv',
                    _buildCsv(_filterByStatus(all, 'queued'), rangeLabel: range),
                  );
                  return;
                }
                if (v == 'csv_failed') {
                  await _exportCsv(
                    'outbound_messages_failed_$slug.csv',
                    _buildCsv(_filterByStatus(all, 'failed'), rangeLabel: range),
                  );
                  return;
                }
                if (v == 'csv_sent') {
                  await _exportCsv(
                    'outbound_messages_sent_$slug.csv',
                    _buildCsv(_filterByStatus(all, 'sent'), rangeLabel: range),
                  );
                  return;
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'csv_all', child: Text('Export: ALL (CSV)')),
                PopupMenuDivider(),
                PopupMenuItem(value: 'csv_queued', child: Text('Export: Queued (CSV)')),
                PopupMenuItem(value: 'csv_failed', child: Text('Export: Failed (CSV)')),
                PopupMenuItem(value: 'csv_sent', child: Text('Export: Sent (CSV)')),
              ],
            ),
          ],
          bottom: TabBar(
            tabs: const [
              Tab(text: 'Queued'),
              Tab(text: 'Opened'),
              Tab(text: 'Failed'),
              Tab(text: 'Sent'),
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
              child: ValueListenableBuilder(
                valueListenable: box.listenable(),
                builder: (context, Box<OutboundMessage> b, _) {
                  final all = b.values.where((m) => _inRange(m, start)).toList();

                  final queued = _filterByStatus(all, 'queued');
                  final opened = _filterByStatus(all, 'opened');
                  final failed = _filterByStatus(all, 'failed');
                  final sent = _filterByStatus(all, 'sent');

                  Widget tabList(List<OutboundMessage> items, String emptyText) {
                    if (items.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(emptyText,
                            style: const TextStyle(color: Colors.black54)),
                      );
                    }
                    return ListView(
                      padding: const EdgeInsets.all(12),
                      children: [for (final m in items) _msgTile(m)],
                    );
                  }

                  return TabBarView(
                    children: [
                      tabList(queued, 'No queued messages in this range.'),
                      tabList(opened, 'No opened messages in this range.'),
                      tabList(failed, 'No failed messages in this range.'),
                      tabList(sent, 'No sent messages in this range.'),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _msgTile(OutboundMessage m) {
    final ch = _st(m.channel).isEmpty ? 'whatsapp' : _st(m.channel);
    final st = _st(m.status).isEmpty ? 'queued' : _st(m.status);

    final body = m.body.trim();
    final preview = body.length <= 120 ? body : '${body.substring(0, 120)}…';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${m.toPhone} • $ch',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Status: $st  • Attempts: ${m.attempts}  • Created: ${_fmt(m.createdAt)}',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            if (_st(m.propertyKey).isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'PropertyKey: ${m.propertyKey}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
            const SizedBox(height: 8),
            Text(preview),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Open'),
                  onPressed: () async {
                    // Force open this exact message (set to queued first so it’s eligible)
                    if (m.status.trim().toLowerCase() == 'sent') return;
                    m.status = 'queued';
                    await m.save();
                    await OutboundMessageService.processQueueOpenNext(
                      channelFilter: ch,
                    );
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Opened $ch composer ✅')),
                    );
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Mark sent'),
                  onPressed: () async {
                    await OutboundMessageService.markSent(m);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Marked sent ✅')),
                    );
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Requeue'),
                  onPressed: () async {
                    m.status = 'queued';
                    await m.save();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Requeued ✅')),
                    );
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.error_outline, size: 18),
                  label: const Text('Fail'),
                  onPressed: () async {
                    await OutboundMessageService.markFailed(
                      m,
                      reason: 'Marked failed by admin from UI',
                    );
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Marked failed ⚠️')),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}