import 'dart:io';

import 'package:bus_cargo_tracker/ui/app_colors.dart';
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

class _AdminOutboundMessagesScreenState
    extends State<AdminOutboundMessagesScreen> {
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

  // Helpers

  String _s(String? v) => v ?? '';
  String _st(String? v) => (v ?? '').trim();
  String _fmt(DateTime? d) =>
      d == null ? '—' : d.toLocal().toString().substring(0, 16);
  String _csvEscape(String v) => '"${v.replaceAll('"', '""')}"';

  bool _inRange(OutboundMessage m, DateTime? startInclusive) {
    if (startInclusive == null) return true;
    return m.createdAt.isAfter(startInclusive) ||
        m.createdAt.isAtSameMomentAs(startInclusive);
  }

  List<OutboundMessage> _filterByStatus(
    List<OutboundMessage> all,
    String status,
  ) {
    return all.where((m) => m.status.trim().toLowerCase() == status).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  // CSV export

  Future<void> _exportCsv(String filename, String csv) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsString(csv, flush: true);
      await Share.shareXFiles([
        XFile(file.path, mimeType: 'text/csv', name: filename),
      ], text: 'Outbound messages export: $filename');
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

  // Actions

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

  // Build

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
                } else if (v == 'csv_queued') {
                  await _exportCsv(
                    'outbound_messages_queued_$slug.csv',
                    _buildCsv(
                      _filterByStatus(all, 'queued'),
                      rangeLabel: range,
                    ),
                  );
                } else if (v == 'csv_failed') {
                  await _exportCsv(
                    'outbound_messages_failed_$slug.csv',
                    _buildCsv(
                      _filterByStatus(all, 'failed'),
                      rangeLabel: range,
                    ),
                  );
                } else if (v == 'csv_sent') {
                  await _exportCsv(
                    'outbound_messages_sent_$slug.csv',
                    _buildCsv(_filterByStatus(all, 'sent'), rangeLabel: range),
                  );
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'csv_all',
                  child: Text('Export: ALL (CSV)'),
                ),
                PopupMenuDivider(),
                PopupMenuItem(
                  value: 'csv_queued',
                  child: Text('Export: Queued (CSV)'),
                ),
                PopupMenuItem(
                  value: 'csv_failed',
                  child: Text('Export: Failed (CSV)'),
                ),
                PopupMenuItem(
                  value: 'csv_sent',
                  child: Text('Export: Sent (CSV)'),
                ),
              ],
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: ValueListenableBuilder(
              valueListenable: box.listenable(),
              builder: (context, Box<OutboundMessage> b, _) {
                final all = b.values.where((m) => _inRange(m, start)).toList();
                final qCount = _filterByStatus(all, 'queued').length;
                final oCount = _filterByStatus(all, 'opened').length;
                final fCount = _filterByStatus(all, 'failed').length;
                final sCount = _filterByStatus(all, 'sent').length;
                return TabBar(
                  tabs: [
                    Tab(text: 'Queued ($qCount)'),
                    Tab(text: 'Opened ($oCount)'),
                    Tab(text: 'Failed ($fCount)'),
                    Tab(text: 'Sent ($sCount)'),
                  ],
                );
              },
            ),
          ),
        ),
        body: Column(
          children: [
            // ── Range selector: inline pill chips ──
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.30),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
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
                        color: Theme.of(context).colorScheme.onSurface,
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

            // ── Tab content ──
            Expanded(
              child: ValueListenableBuilder(
                valueListenable: box.listenable(),
                builder: (context, Box<OutboundMessage> b, _) {
                  final all = b.values
                      .where((m) => _inRange(m, _startInclusive()))
                      .toList();
                  final queued = _filterByStatus(all, 'queued');
                  final opened = _filterByStatus(all, 'opened');
                  final failed = _filterByStatus(all, 'failed');
                  final sent = _filterByStatus(all, 'sent');

                  return TabBarView(
                    children: [
                      _tabList(
                        queued,
                        Icons.hourglass_top_outlined,
                        'No queued messages in this range.',
                      ),
                      _tabList(
                        opened,
                        Icons.drafts_outlined,
                        'No opened messages in this range.',
                      ),
                      _tabList(
                        failed,
                        Icons.error_outline,
                        'No failed messages in this range.',
                      ),
                      _tabList(
                        sent,
                        Icons.check_circle_outline,
                        'No sent messages in this range.',
                      ),
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

  // Tab list

  Widget _tabList(
    List<OutboundMessage> items,
    IconData emptyIcon,
    String emptyText,
  ) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Row(
          children: [
            Icon(emptyIcon, size: 16, color: Colors.black38),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                emptyText,
                style: const TextStyle(color: Colors.black54, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
      children: [for (final m in items) _msgTile(m)],
    );
  }

  // Message tile

  Widget _msgTile(OutboundMessage m) {
    final ch = _st(m.channel).isEmpty ? 'whatsapp' : _st(m.channel);
    final st = _st(m.status).isEmpty ? 'queued' : _st(m.status);
    final body = m.body.trim();
    final preview = body.length <= 120 ? body : '${body.substring(0, 120)}…';
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.55);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header: avatar + phone + status pill ──
            Row(
              children: [
                _channelAvatar(ch),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.toPhone,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        ch.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          color: _channelColor(ch),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _statusPill(st),
                    const SizedBox(height: 4),
                    Text(
                      _fmt(m.createdAt),
                      style: TextStyle(fontSize: 10, color: muted),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 8),

            // ── Meta row ──
            Row(
              children: [
                Icon(Icons.repeat_outlined, size: 13, color: muted),
                const SizedBox(width: 4),
                Text(
                  'Attempts: ${m.attempts}',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
                if (_st(m.propertyKey).isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.inventory_2_outlined, size: 13, color: muted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      m.propertyKey,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 8),

            // ── Message body ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.30),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(preview, style: const TextStyle(fontSize: 13)),
            ),

            const SizedBox(height: 10),

            // ── Action buttons ──
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _tileButton(
                  icon: Icons.open_in_new_outlined,
                  label: 'Open',
                  onTap: st == 'sent'
                      ? null
                      : () async {
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
                _tileButton(
                  icon: Icons.check_circle_outline,
                  label: 'Mark sent',
                  onTap: () async {
                    await OutboundMessageService.markSent(m);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Marked sent ✅')),
                    );
                  },
                ),
                _tileButton(
                  icon: Icons.refresh_outlined,
                  label: 'Requeue',
                  onTap: () async {
                    m.status = 'queued';
                    await m.save();
                    if (!mounted) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('Requeued ✅')));
                  },
                ),
                _tileButton(
                  icon: Icons.cancel_outlined,
                  label: 'Fail',
                  onTap: () async {
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

  // Small UI helpers

  /// Inline pill range selector
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

  /// Channel avatar: colored rounded square icon
  Widget _channelAvatar(String ch) {
    final color = _channelColor(ch);
    final icon = ch.toLowerCase() == 'sms'
        ? Icons.sms_outlined
        : Icons.chat_outlined;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }

  Color _channelColor(String ch) =>
      ch.toLowerCase() == 'sms' ? Colors.blue : Colors.green;

  /// Colored status pill (inline Container, not Flutter Chip)
  Widget _statusPill(String status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Color _statusColor(String s) {
    switch (s.toLowerCase()) {
      case 'queued':
        return Colors.amber.shade700;
      case 'opened':
        return Colors.blue;
      case 'sent':
        return Colors.green;
      case 'failed':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  /// Compact outlined tile action button
  Widget _tileButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 15),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: BorderSide(
          color: onTap == null ? Colors.grey : AppColors.primary,
        ),
        foregroundColor: onTap == null ? Colors.grey : AppColors.primary,
      ),
    );
  }
}
