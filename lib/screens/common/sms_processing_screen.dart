import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/outbound_message.dart';
import '../../models/user_role.dart';
import '../../services/hive_service.dart';
import '../../services/outbound_message_service.dart';
import '../../services/role_guard.dart';

class SmsProcessingScreen extends StatefulWidget {
  const SmsProcessingScreen({super.key});

  @override
  State<SmsProcessingScreen> createState() => _SmsProcessingScreenState();
}

class _SmsProcessingScreenState extends State<SmsProcessingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _controller;
  bool _busy = false;

  bool get _canUse =>
      RoleGuard.hasAny({UserRole.deskCargoOfficer, UserRole.admin});

  @override
  void initState() {
    super.initState();
    _controller = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }


  List<OutboundMessage> _itemsForStatus(
    Box<OutboundMessage> box,
    String status,
  ) {
    final items = box.values.where((m) {
      final ch = m.channel.trim().toLowerCase();
      final st = m.status.trim().toLowerCase();
      return ch == 'sms' && st == status;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  int _countForStatus(Box<OutboundMessage> box, String status) {
    return box.values.where((m) {
      final ch = m.channel.trim().toLowerCase();
      final st = m.status.trim().toLowerCase();
      return ch == 'sms' && st == status;
    }).length;
  }

  Future<void> _openNextSms() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final msg = await OutboundMessageService.processQueueOpenNext(
        channelFilter: 'sms',
      );

      if (!mounted) return;

      if (msg == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No eligible SMS to open ✅')),
        );
        return;
      }

      final st = msg.status.trim().toLowerCase();
      if (st == OutboundMessageService.statusOpened) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Opened SMS for: ${msg.toPhone}')),
        );
        _controller.animateTo(1);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open SMS for: ${msg.toPhone}')),
        );
        _controller.animateTo(2);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openThis(OutboundMessage msg) async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final res = await OutboundMessageService.openSpecific(msg);

      if (!mounted) return;
      if (res == null) return;

      final st = res.status.trim().toLowerCase();
      if (st == OutboundMessageService.statusOpened) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Opened SMS for: ${res.toPhone}')),
        );
        _controller.animateTo(1);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open SMS for: ${res.toPhone}')),
        );
        _controller.animateTo(2);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markSent(OutboundMessage msg) async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      await OutboundMessageService.markSent(msg);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marked as sent ✅')),
      );

      _controller.animateTo(3);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markFailed(OutboundMessage msg) async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      await OutboundMessageService.markFailed(
        msg,
        reason: 'Operator marked failed (SMS)',
      );
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marked as failed ⚠️')),
      );

      _controller.animateTo(2);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyToClipboard(String text, {String? toast}) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(toast ?? 'Copied ✅')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_canUse) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    final box = HiveService.outboundMessageBox();

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('SMS Processing'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: AnimatedBuilder(
            animation: Listenable.merge([box.listenable(), _controller]),
            builder: (_, __) {
              final q = _countForStatus(box, OutboundMessageService.statusQueued);
              final o = _countForStatus(box, OutboundMessageService.statusOpened);
              final f = _countForStatus(box, OutboundMessageService.statusFailed);
              final s = _countForStatus(box, OutboundMessageService.statusSent);

              return TabBar(
                controller: _controller,
                tabs: [
                  Tab(text: 'Queued ($q)'),
                  Tab(text: 'Opened ($o)'),
                  Tab(text: 'Failed ($f)'),
                  Tab(text: 'Sent ($s)'),
                ],
              );
            },
          ),
        ),
        actions: [
          IconButton(
            tooltip: _busy ? 'Working...' : 'Open next SMS',
            icon: const Icon(Icons.sms_outlined),
            onPressed: _busy ? null : _openNextSms,
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([box.listenable(), _controller]),
        builder: (context, _) {
          return TabBarView(
            controller: _controller,
            children: [
              _tabList(box, OutboundMessageService.statusQueued),
              _tabList(box, OutboundMessageService.statusOpened),
              _tabList(box, OutboundMessageService.statusFailed),
              _tabList(box, OutboundMessageService.statusSent),
            ],
          );
        },
      ),
    );
  }

  Widget _tabList(Box<OutboundMessage> box, String status) {
    final items = _itemsForStatus(box, status);

    final label = status == OutboundMessageService.statusQueued
        ? 'Queued'
        : status == OutboundMessageService.statusOpened
            ? 'Opened'
            : status == OutboundMessageService.statusFailed
                ? 'Failed'
                : 'Sent';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$label SMS: ${items.length}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _busy ? null : _openNextSms,
                    icon: const Icon(Icons.open_in_new),
                    label: Text(_busy ? 'Working...' : 'Open next'),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const Center(child: Text('No SMS messages here.'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _tile(items[i]),
                ),
        ),
      ],
    );
  }

  Widget _tile(OutboundMessage m) {
    final when = m.createdAt.toLocal().toString().substring(0, 16);
    final st = m.status.trim().toLowerCase();
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.60);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onLongPress: () async {
          final choice = await showModalBottomSheet<String>(
            context: context,
            showDragHandle: true,
            builder: (ctx) {
              return SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.copy),
                      title: const Text('Copy phone'),
                      subtitle: Text(m.toPhone),
                      onTap: () => Navigator.pop(ctx, 'phone'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.copy),
                      title: const Text('Copy message'),
                      subtitle: Text(
                        m.body.length > 60 ? '${m.body.substring(0, 60)}…' : m.body,
                      ),
                      onTap: () => Navigator.pop(ctx, 'body'),
                    ),
                    if (m.propertyKey.trim().isNotEmpty)
                      ListTile(
                        leading: const Icon(Icons.copy),
                        title: const Text('Copy property key'),
                        subtitle: Text(m.propertyKey),
                        onTap: () => Navigator.pop(ctx, 'property'),
                      ),
                    const SizedBox(height: 6),
                  ],
                ),
              );
            },
          );

          if (choice == 'phone') {
            await _copyToClipboard(m.toPhone, toast: 'Phone copied ✅');
          } else if (choice == 'body') {
            await _copyToClipboard(m.body, toast: 'Message copied ✅');
          } else if (choice == 'property') {
            await _copyToClipboard(m.propertyKey, toast: 'Property key copied ✅');
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'SMS → ${m.toPhone}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(when, style: TextStyle(fontSize: 12, color: muted)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Property: ${m.propertyKey.trim().isEmpty ? '—' : m.propertyKey}',
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 8),
              Text(m.body),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    'Status: ${m.status} | Attempts: ${m.attempts}',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                  const Spacer(),
                  if (st == OutboundMessageService.statusQueued ||
                      st == OutboundMessageService.statusFailed)
                    OutlinedButton(
                      onPressed: _busy ? null : () => _openThis(m),
                      child: const Text('Open'),
                    ),
                  if (st == OutboundMessageService.statusOpened) ...[
                    OutlinedButton(
                      onPressed: _busy ? null : () => _markFailed(m),
                      child: const Text('Mark failed'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _busy ? null : () => _markSent(m),
                      child: const Text('Mark sent'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}