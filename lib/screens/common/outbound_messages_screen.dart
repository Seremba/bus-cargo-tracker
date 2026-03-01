import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/outbound_message.dart';
import '../../models/user_role.dart';
import '../../services/hive_service.dart';
import '../../services/outbound_message_service.dart';
import '../../services/role_guard.dart';

class OutboundMessagesScreen extends StatefulWidget {
  /// Optional channel-only mode: 'sms' or 'whatsapp'
  final String? channelFilter;

  /// Optional title override
  final String? title;

  const OutboundMessagesScreen({super.key, this.channelFilter, this.title});

  @override
  State<OutboundMessagesScreen> createState() => _OutboundMessagesScreenState();
}

class _OutboundMessagesScreenState extends State<OutboundMessagesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _controller;
  bool _busy = false;

  bool get _canUse =>
      RoleGuard.hasAny({UserRole.deskCargoOfficer, UserRole.admin});

  String get _filterCh => (widget.channelFilter ?? '').trim().toLowerCase();
  bool get _hasFilter => _filterCh.isNotEmpty;

  String get _screenTitle {
    if ((widget.title ?? '').trim().isNotEmpty) return widget.title!.trim();
    if (_filterCh == 'sms') return 'SMS Processing';
    if (_filterCh == 'whatsapp') return 'WhatsApp Processing';
    return 'Outbound Messages';
  }

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
      final msg = await OutboundMessageService.processQueueOpenNext(
        channelFilter: _hasFilter ? _filterCh : null,
      );

      if (!mounted) return;

      if (msg == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _hasFilter
                  ? 'No eligible ${_filterCh.toUpperCase()} messages to open ✅'
                  : 'No eligible messages to open ✅',
            ),
          ),
        );
        return;
      }

      final st = msg.status.trim().toLowerCase();
      final ch = msg.channel.trim().isEmpty
          ? 'whatsapp'
          : msg.channel.trim().toLowerCase();

      if (st == OutboundMessageService.statusOpened) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Opened ${ch.toUpperCase()} for: ${msg.toPhone}'),
          ),
        );
        _controller.animateTo(1); // Opened
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to open ${ch.toUpperCase()} for: ${msg.toPhone}',
            ),
          ),
        );
        _controller.animateTo(2); // Failed
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed: $e')));
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

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Marked as sent ✅')));

      _controller.animateTo(3);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed: $e')));
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

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Marked as failed ⚠️')));

      // ✅ NEW: jump to Failed tab
      _controller.animateTo(2);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed: $e')));
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
        title: Text(_screenTitle),
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
            tooltip: _busy ? 'Working...' : 'Open next',
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

          final items = b.values.whereType<OutboundMessage>().where((m) {
            final st = m.status.trim().toLowerCase();
            if (st != status) return false;

            if (!_hasFilter) return true;
            final ch = m.channel.trim().toLowerCase();
            return ch == _filterCh;
          }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          final label = _controller.index == 0
              ? 'Queued'
              : _controller.index == 1
              ? 'Opened'
              : _controller.index == 2
              ? 'Failed'
              : 'Sent';

          final header = _hasFilter
              ? '$label ${_filterCh.toUpperCase()}'
              : label;

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
                            '$header: ${items.length}',
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
    final st = m.status.trim().toLowerCase();
    final ch = m.channel.trim().isEmpty ? 'whatsapp' : m.channel.trim();

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
                    '${ch.toUpperCase()} → ${m.toPhone}',
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
                if (st == OutboundMessageService.statusQueued ||
                    st == OutboundMessageService.statusFailed) ...[
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
