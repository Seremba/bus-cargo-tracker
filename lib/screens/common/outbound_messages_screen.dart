import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/outbound_message.dart';
import '../../models/user_role.dart';
import '../../services/hive_service.dart';
import '../../services/outbound_message_service.dart';
import '../../services/role_guard.dart';

class OutboundMessagesScreen extends StatefulWidget {
  /// Optional initial channel mode: 'sms' or 'whatsapp'
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

  // values: 'all' | 'sms' | 'whatsapp'
  late String _channelMode;

  bool get _canUse =>
      RoleGuard.hasAny({UserRole.deskCargoOfficer, UserRole.admin});

  String get _screenTitle {
    if ((widget.title ?? '').trim().isNotEmpty) return widget.title!.trim();
    if (_channelMode == 'sms') return 'SMS Processing';
    if (_channelMode == 'whatsapp') return 'WhatsApp Processing';
    return 'Outbound Messages';
  }

  @override
  void initState() {
    super.initState();
    _controller = TabController(length: 4, vsync: this);

    final initial = (widget.channelFilter ?? '').trim().toLowerCase();
    _channelMode = (initial == 'sms' || initial == 'whatsapp') ? initial : 'all';
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

  bool _passesChannel(OutboundMessage m) {
    if (_channelMode == 'all') return true;
    final ch = m.channel.trim().toLowerCase();
    return ch == _channelMode;
  }

  Future<void> _openNext() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final msg = await OutboundMessageService.processQueueOpenNext(
        channelFilter: _channelMode == 'all' ? null : _channelMode,
      );

      if (!mounted) return;

      if (msg == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _channelMode == 'all'
                  ? 'No eligible messages to open ✅'
                  : 'No eligible ${_channelMode.toUpperCase()} messages to open ✅',
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
          SnackBar(content: Text('Opened ${ch.toUpperCase()} for: ${msg.toPhone}')),
        );
        _controller.animateTo(1); // Opened
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open ${ch.toUpperCase()} for: ${msg.toPhone}')),
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

  Future<void> _openSpecific(OutboundMessage msg) async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final res = await OutboundMessageService.openSpecific(msg);

      if (!mounted) return;
      if (res == null) return;

      final st = res.status.trim().toLowerCase();
      final ch = res.channel.trim().isEmpty
          ? 'whatsapp'
          : res.channel.trim().toLowerCase();

      if (st == OutboundMessageService.statusOpened) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Opened ${ch.toUpperCase()} for: ${res.toPhone}')),
        );
        _controller.animateTo(1); // Opened
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open ${ch.toUpperCase()} for: ${res.toPhone}')),
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

      // UX: jump to Sent tab
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
        reason: 'Operator marked failed',
      );
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marked as failed ⚠️')),
      );

      // UX: jump to Failed tab
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
          // Filter dropdown (All / SMS / WhatsApp)
          DropdownButtonHideUnderline(
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: DropdownButton<String>(
                value: _channelMode,
                dropdownColor: Theme.of(context).colorScheme.surface,
                icon: const Icon(Icons.filter_list),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All')),
                  DropdownMenuItem(value: 'sms', child: Text('SMS')),
                  DropdownMenuItem(value: 'whatsapp', child: Text('WhatsApp')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _channelMode = v);
                },
              ),
            ),
          ),
          IconButton(
            tooltip: _busy ? 'Working...' : 'Open next',
            icon: const Icon(Icons.send_outlined),
            onPressed: _busy ? null : _openNext,
          ),
        ],
      ),

      // ✅ IMPORTANT: rebuild on BOTH tab changes and box changes
      body: AnimatedBuilder(
        animation: Listenable.merge([box.listenable(), _controller]),
        builder: (context, _) {
          final tabIndex = _controller.index;
          final status = _statusForTab(tabIndex);

          final items = box.values
              .where((m) {
                final st = m.status.trim().toLowerCase();
                if (st != status) return false;
                return _passesChannel(m);
              })
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          final label = tabIndex == 0
              ? 'Queued'
              : tabIndex == 1
                  ? 'Opened'
                  : tabIndex == 2
                      ? 'Failed'
                      : 'Sent';

          final header = _channelMode == 'all'
              ? label
              : '$label ${_channelMode.toUpperCase()}';

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

                if (st == OutboundMessageService.statusQueued ||
                    st == OutboundMessageService.statusFailed)
                  OutlinedButton(
                    onPressed: _busy ? null : () => _openSpecific(m),
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
    );
  }
}