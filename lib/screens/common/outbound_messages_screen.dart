import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/outbound_message.dart';
import '../../models/user_role.dart';
import '../../services/hive_service.dart';
import '../../services/outbound_message_service.dart';
import '../../services/role_guard.dart';

class OutboundMessagesScreen extends StatefulWidget {
  const OutboundMessagesScreen({super.key});

  @override
  State<OutboundMessagesScreen> createState() => _OutboundMessagesScreenState();
}

class _OutboundMessagesScreenState extends State<OutboundMessagesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _controller;

  bool _busy = false;

  bool get _canUse => RoleGuard.hasAny({
        UserRole.deskCargoOfficer,
        UserRole.admin,
      });

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

  String _statusForTab(int i) {
    switch (i) {
      case 0:
        return OutboundMessageService.statusQueued;
      case 1:
        return OutboundMessageService.statusOpened;
      case 2:
        return OutboundMessageService.statusFailed;
      case 3:
        return OutboundMessageService.statusSent;
      default:
        return OutboundMessageService.statusQueued;
    }
  }

  Future<void> _openNext() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final msg = await OutboundMessageService.processQueueOpenNext();
      if (!mounted) return;

      if (msg == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No eligible messages to open ✅')),
        );
        return;
      }

      final st = msg.status.trim().toLowerCase();
      if (st == OutboundMessageService.statusOpened) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Opened WhatsApp for: ${msg.toPhone}')),
        );
        _controller.animateTo(1); // Opened
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open composer for: ${msg.toPhone}')),
        );
        _controller.animateTo(2); // Failed
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
        reason: 'Operator marked failed',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marked as failed ⚠️')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
        title: const Text('Outbound Messages'),
        bottom: TabBar(
          controller: _controller,
          tabs: const [
            Tab(text: 'Queued'),
            Tab(text: 'Opened'),
            Tab(text: 'Failed'),
            Tab(text: 'Sent'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Open next',
            icon: const Icon(Icons.send_outlined),
            onPressed: _busy ? null : _openNext,
          ),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: box.listenable(),
        builder: (context, Box b, _) {
          final tabIndex = _controller.index;
          final status = _statusForTab(tabIndex);

          final items = b.values
              .whereType<OutboundMessage>()
              .where((m) => m.status.trim().toLowerCase() == status)
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

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
                            '${_controller.index == 0 ? 'Queued' : _controller.index == 1 ? 'Opened' : _controller.index == 2 ? 'Failed' : 'Sent'}: ${items.length}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _busy ? null : _openNext,
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
                    ? const Center(child: Text('No messages here.'))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: items.length,
                        itemBuilder: (_, i) => _tile(items[i]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _tile(OutboundMessage m) {
    final when = m.createdAt.toLocal().toString().substring(0, 16);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${m.channel.toUpperCase()} → ${m.toPhone}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  when,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Property: ${m.propertyKey.isEmpty ? '—' : m.propertyKey}',
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 8),
            Text(m.body),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  'Status: ${m.status} | Attempts: ${m.attempts}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const Spacer(),
                if (m.status.trim().toLowerCase() ==
                    OutboundMessageService.statusOpened) ...[
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
                if (m.status.trim().toLowerCase() ==
                        OutboundMessageService.statusQueued ||
                    m.status.trim().toLowerCase() ==
                        OutboundMessageService.statusFailed) ...[
                  OutlinedButton(
                    onPressed: _busy ? null : _openNext,
                    child: const Text('Open next'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}