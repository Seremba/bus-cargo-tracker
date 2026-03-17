import 'package:bus_cargo_tracker/ui/app_colors.dart';
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
    return m.channel.trim().toLowerCase() == _channelMode;
  }

  int _countForStatus(Box<OutboundMessage> box, String status) {
    return box.values.where((m) {
      if (m.status.trim().toLowerCase() != status) return false;
      return _passesChannel(m);
    }).length;
  }

  Future<void> _requeueOpenedNow() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final box = HiveService.outboundMessageBox();
      final beforeOpened = box.values
          .where(
            (m) =>
                m.status.trim().toLowerCase() ==
                    OutboundMessageService.statusOpened &&
                _passesChannel(m),
          )
          .length;

      await OutboundMessageService.requeueOpenedMessages();

      if (!mounted) return;
      final afterOpened = box.values
          .where(
            (m) =>
                m.status.trim().toLowerCase() ==
                    OutboundMessageService.statusOpened &&
                _passesChannel(m),
          )
          .length;
      final n = beforeOpened - afterOpened;

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
      if (m.status.trim().toLowerCase() != status) return false;
      return _passesChannel(m);
    }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final channelLabel = _channelMode == 'all'
        ? ''
        : ' · ${_channelMode.toUpperCase()}';

    String statusLabel;
    switch (status) {
      case 'queued':
        statusLabel = 'Queued';
        break;
      case 'opened':
        statusLabel = 'Opened';
        break;
      case 'failed':
        statusLabel = 'Failed';
        break;
      default:
        statusLabel = 'Sent';
    }

    return Column(
      children: [
        // ── Info + action bar ──
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                Icon(Icons.info_outline, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$statusLabel$channelLabel: ${items.length}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (_isAdmin) ...[
                  const SizedBox(width: 6),
                  _actionButton(
                    label: 'Requeue',
                    icon: Icons.refresh_outlined,
                    onTap: _busy ? null : _requeueOpenedNow,
                    outlined: true,
                  ),
                ],
                const SizedBox(width: 8),
                _actionButton(
                  label: _busy ? 'Working…' : 'Open next',
                  icon: Icons.open_in_new_outlined,
                  onTap: _busy ? null : _openNext,
                  outlined: false,
                ),
              ],
            ),
          ),
        ),

        // ── Channel filter pills ──
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: Row(
            children: [
              _channelPill('all', 'All'),
              const SizedBox(width: 6),
              _channelPill('sms', 'SMS'),
              const SizedBox(width: 6),
              _channelPill('whatsapp', 'WhatsApp'),
            ],
          ),
        ),

        // ── List ──
        Expanded(
          child: items.isEmpty
              ? _emptyState(Icons.mail_outline, 'No messages here.')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _tile(items[i]),
                ),
        ),
      ],
    );
  }

  // ── Compact action button ──
  Widget _actionButton({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
    required bool outlined,
  }) {
    if (outlined) {
      return OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 15),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          side: BorderSide(color: AppColors.primary),
          foregroundColor: AppColors.primary,
        ),
      );
    }
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 15),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  // ── Channel pill (replaces DropdownButton) ──
  Widget _channelPill(String mode, String label) {
    final active = _channelMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _channelMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
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

  Widget _tile(OutboundMessage m) {
    final when = m.createdAt.toLocal().toString().substring(0, 16);
    final st = m.status.trim().toLowerCase();
    final ch = m.channel.trim().isEmpty ? 'whatsapp' : m.channel.trim();
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.55);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onLongPress: () async {
          final choice = await showModalBottomSheet<String>(
            context: context,
            showDragHandle: true,
            builder: (ctx) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.copy_outlined),
                    title: const Text('Copy phone'),
                    subtitle: Text(m.toPhone),
                    onTap: () => Navigator.pop(ctx, 'phone'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.copy_outlined),
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
                      leading: const Icon(Icons.copy_outlined),
                      title: const Text('Copy property key'),
                      subtitle: Text(m.propertyKey),
                      onTap: () => Navigator.pop(ctx, 'property'),
                    ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
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
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header row: channel avatar + phone + timestamp ──
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
                      _statusPill(m.status),
                      const SizedBox(height: 4),
                      Text(when, style: TextStyle(fontSize: 10, color: muted)),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // ── Property key row ──
              if (m.propertyKey.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 13, color: muted),
                      const SizedBox(width: 4),
                      Text(
                        m.propertyKey,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                  ),
                ),

              // ── Message body ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(m.body, style: const TextStyle(fontSize: 13)),
              ),

              const SizedBox(height: 8),

              // ── Footer row: attempts + action buttons ──
              Row(
                children: [
                  Icon(Icons.repeat_outlined, size: 13, color: muted),
                  const SizedBox(width: 4),
                  Text(
                    'Attempts: ${m.attempts}',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                  const Spacer(),
                  if (st == OutboundMessageService.statusQueued ||
                      st == OutboundMessageService.statusFailed)
                    _actionButton(
                      label: 'Open',
                      icon: Icons.open_in_new_outlined,
                      onTap: _busy ? null : () => _openSpecific(m),
                      outlined: true,
                    ),
                  if (st == OutboundMessageService.statusOpened) ...[
                    _actionButton(
                      label: 'Mark failed',
                      icon: Icons.cancel_outlined,
                      onTap: _busy ? null : () => _markFailed(m),
                      outlined: true,
                    ),
                    const SizedBox(width: 8),
                    _actionButton(
                      label: 'Mark sent',
                      icon: Icons.check_circle_outline,
                      onTap: _busy ? null : () => _markSent(m),
                      outlined: false,
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

  Widget _channelAvatar(String ch) {
    final color = _channelColor(ch);
    IconData icon;
    if (ch.toLowerCase() == 'sms') {
      icon = Icons.sms_outlined;
    } else {
      icon = Icons.chat_outlined;
    }
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

  Color _channelColor(String ch) {
    return ch.toLowerCase() == 'sms' ? Colors.blue : Colors.green;
  }

  Widget _statusPill(String status) {
    final color = _statusColor(status.toLowerCase());
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
    switch (s) {
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

  /// Empty state: icon + message (never plain text alone)
  Widget _emptyState(IconData icon, String message) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.black38),
          const SizedBox(width: 8),
          Text(
            message,
            style: const TextStyle(color: Colors.black54, fontSize: 14),
          ),
        ],
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
        actions: [
          if (_isAdmin)
            IconButton(
              tooltip: _busy ? 'Working...' : 'Requeue opened',
              icon: const Icon(Icons.refresh_outlined),
              onPressed: _busy ? null : _requeueOpenedNow,
            ),
          IconButton(
            tooltip: _busy ? 'Working...' : 'Open next',
            icon: const Icon(Icons.send_outlined),
            onPressed: _busy ? null : _openNext,
          ),
        ],
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
      ),
      body: ValueListenableBuilder(
        valueListenable: box.listenable(),
        builder: (context, Box<OutboundMessage> b, _) {
          return TabBarView(
            controller: _controller,
            physics: const NeverScrollableScrollPhysics(),
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
