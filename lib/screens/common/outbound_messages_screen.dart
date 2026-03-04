import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/outbound_message.dart';
import '../../models/user_role.dart';
import '../../services/hive_service.dart';
import '../../services/outbound_message_service.dart';
import '../../services/role_guard.dart';

class OutboundMessagesScreen extends StatefulWidget {
  final String? channelFilter;

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

  bool get _isAdmin => RoleGuard.hasRole(UserRole.admin);

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
    _channelMode = (initial == 'sms' || initial == 'whatsapp')
        ? initial
        : 'all';
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

  int _countForStatus(Box<OutboundMessage> box, String status) {
    return box.values.where((m) {
      final st = m.status.trim().toLowerCase();
      if (st != status) return false;
      return _passesChannel(m);
    }).length;
  }

  Future<void> _requeueOpenedNow() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final box = HiveService.outboundMessageBox();

      final beforeOpened = box.values.where((m) {
        final st = m.status.trim().toLowerCase();
        if (st != OutboundMessageService.statusOpened) return false;
        return _passesChannel(m);
      }).length;

      await OutboundMessageService.requeueOpenedMessages();

      if (!mounted) return;

      final afterOpened = box.values.where((m) {
        final st = m.status.trim().toLowerCase();
        if (st != OutboundMessageService.statusOpened) return false;
        return _passesChannel(m);
      }).length;

      final n = (beforeOpened - afterOpened);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            n <= 0
                ? 'No OPENED messages to requeue ✅'
                : 'Requeued $n OPENED message(s) ✅',
          ),
        ),
      );

      _controller.animateTo(0);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
          SnackBar(
            content: Text('Opened ${ch.toUpperCase()} for: ${msg.toPhone}'),
          ),
        );
        _controller.animateTo(1);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to open ${ch.toUpperCase()} for: ${msg.toPhone}',
            ),
          ),
        );
        _controller.animateTo(2);
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
          SnackBar(
            content: Text('Opened ${ch.toUpperCase()} for: ${res.toPhone}'),
          ),
        );
        _controller.animateTo(1);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to open ${ch.toUpperCase()} for: ${res.toPhone}',
            ),
          ),
        );
        _controller.animateTo(2);
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

  Future<void> _copyToClipboard(String text, {String? toast}) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(toast ?? 'Copied ✅')));
  }

  Widget _buildTab(Box<OutboundMessage> box, String status) {
    final items = box.values.where((m) {
      final st = m.status.trim().toLowerCase();
      if (st != status) return false;
      return _passesChannel(m);
    }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.60);

    String headerLabel;
    if (status == OutboundMessageService.statusQueued) {
      headerLabel = 'Queued';
    } else if (status == OutboundMessageService.statusOpened) {
      headerLabel = 'Opened';
    } else if (status == OutboundMessageService.statusFailed) {
      headerLabel = 'Failed';
    } else {
      headerLabel = 'Sent';
    }

    final header = _channelMode == 'all'
        ? headerLabel
        : '$headerLabel ${_channelMode.toUpperCase()}';

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
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (_isAdmin)
                    TextButton.icon(
                      onPressed: _busy ? null : _requeueOpenedNow,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Requeue'),
                    ),
                  const SizedBox(width: 6),
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
              ? Center(
                  child: Text(
                    'No messages here.',
                    style: TextStyle(color: muted),
                  ),
                )
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
    final ch = m.channel.trim().isEmpty ? 'whatsapp' : m.channel.trim();

    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.60);

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
                        m.body.length > 60
                            ? '${m.body.substring(0, 60)}…'
                            : m.body,
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
            await _copyToClipboard(
              m.propertyKey,
              toast: 'Property key copied ✅',
            );
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
                      '${ch.toUpperCase()} → ${m.toPhone}',
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
      ),
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
        title: Text(_screenTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: ValueListenableBuilder(
            valueListenable: box.listenable(),
            builder: (context, Box<OutboundMessage> b, _) {
              final q = _countForStatus(b, OutboundMessageService.statusQueued);
              final o = _countForStatus(b, OutboundMessageService.statusOpened);
              final f = _countForStatus(b, OutboundMessageService.statusFailed);
              final s = _countForStatus(b, OutboundMessageService.statusSent);

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
          if (_isAdmin)
            IconButton(
              tooltip: _busy ? 'Working...' : 'Requeue opened',
              icon: const Icon(Icons.refresh),
              onPressed: _busy ? null : _requeueOpenedNow,
            ),
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

      body: ValueListenableBuilder(
        valueListenable: box.listenable(),
        builder: (context, Box<OutboundMessage> b, _) {
          return TabBarView(
            controller: _controller,
            physics:
                const NeverScrollableScrollPhysics(), // optional but recommended
            children: [
              _buildTab(b, _statusForTab(0)),
              _buildTab(b, _statusForTab(1)),
              _buildTab(b, _statusForTab(2)),
              _buildTab(b, _statusForTab(3)),
            ],
          );
        },
      ),
    );
  }
}
