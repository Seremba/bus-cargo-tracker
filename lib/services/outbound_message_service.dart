import 'dart:math';

import 'package:url_launcher/url_launcher.dart';

import '../models/outbound_message.dart';
import 'audit_service.dart';
import 'hive_service.dart';
import 'whatsapp_service.dart';

class OutboundMessageService {
  OutboundMessageService._();

  static String _id() => DateTime.now().millisecondsSinceEpoch.toString();

  // Status values (keep as strings for Hive simplicity)
  static const String statusQueued = 'queued';
  static const String statusOpened = 'opened'; // opened in WhatsApp/SMS composer
  static const String statusSent = 'sent';
  static const String statusFailed = 'failed';

  static const int maxAttempts = 6;

  static Future<OutboundMessage> queue({
    required String toPhone,
    required String body,
    String channel = 'whatsapp',
    required String propertyKey,
  }) async {
    final box = HiveService.outboundMessageBox();

    final msg = OutboundMessage(
      id: _id(),
      toPhone: toPhone.trim(),
      channel: channel.trim().isEmpty ? 'whatsapp' : channel.trim(),
      body: body,
      createdAt: DateTime.now(),
      propertyKey: propertyKey,
      status: statusQueued,
      attempts: 0,
    );

    await box.add(msg);

    await AuditService.log(
      action: 'OUTBOUND_MSG_QUEUED',
      propertyKey: propertyKey,
      details: 'Queued outbound message: channel=${msg.channel} to=${msg.toPhone}',
    );

    return msg;
  }

  /// Operator-assisted queue processing:
  /// - Picks next eligible message (queued/failed) using backoff.
  /// - Opens WhatsApp OR SMS with prefilled text.
  /// - Marks message as "opened" to avoid immediate re-pop.
  ///
  /// Returns the message that was attempted (opened or failed), or null if none eligible.
  static Future<OutboundMessage?> processQueueOpenNext({
    String? channelFilter, // 'whatsapp'/'sms' if needed
  }) async {
    final box = HiveService.outboundMessageBox();
    final now = DateTime.now();

    final filterCh = (channelFilter ?? '').trim().toLowerCase();
    final hasChannelFilter = filterCh.isNotEmpty;

    final candidates = box.values
        .whereType<OutboundMessage>()
        .where((m) {
          final st = (m.status).trim().toLowerCase();
          final ch = (m.channel).trim().toLowerCase();

          final allowedStatus = (st == statusQueued || st == statusFailed);
          if (!allowedStatus) return false;

          if (hasChannelFilter && ch != filterCh) return false;

          if (m.attempts >= maxAttempts) return false;

          // Backoff: if lastAttemptAt exists, wait a bit before retrying
          final wait = _backoffForAttempts(m.attempts);
          if (m.lastAttemptAt != null) {
            final dueAt = m.lastAttemptAt!.add(wait);
            if (now.isBefore(dueAt)) return false;
          }

          return true;
        })
        .toList();

    if (candidates.isEmpty) return null;

    // Oldest first (fair queue)
    candidates.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final msg = candidates.first;

    final ok = await _openComposer(msg);

    msg.attempts = msg.attempts + 1;
    msg.lastAttemptAt = now;

    if (ok) {
      msg.status = statusOpened;
      await msg.save();

      await AuditService.log(
        action: 'OUTBOUND_MSG_OPENED',
        propertyKey: msg.propertyKey,
        details:
            'Opened composer for outbound message id=${msg.id} channel=${msg.channel} to=${msg.toPhone}',
      );

      return msg;
    } else {
      msg.status = statusFailed;
      await msg.save();

      await AuditService.log(
        action: 'OUTBOUND_MSG_OPEN_FAILED',
        propertyKey: msg.propertyKey,
        details:
            'Failed to open composer for outbound message id=${msg.id} channel=${msg.channel} to=${msg.toPhone}',
      );

      // ✅ return msg so UI can display the failure and allow manual actions
      return msg;
    }
  }

  /// Mark message as SENT (call this from UI after user confirms it was sent).
  static Future<void> markSent(OutboundMessage msg) async {
    msg.status = statusSent;
    await msg.save();

    await AuditService.log(
      action: 'OUTBOUND_MSG_SENT',
      propertyKey: msg.propertyKey,
      details: 'Marked sent: id=${msg.id} channel=${msg.channel} to=${msg.toPhone}',
    );
  }

  /// Mark message as FAILED (call this from UI if user cancels/WhatsApp/SMS failed).
  static Future<void> markFailed(
    OutboundMessage msg, {
    String reason = '',
  }) async {
    msg.status = statusFailed;
    await msg.save();

    await AuditService.log(
      action: 'OUTBOUND_MSG_FAILED',
      propertyKey: msg.propertyKey,
      details:
          'Marked failed: id=${msg.id} channel=${msg.channel} to=${msg.toPhone}. ${reason.trim()}',
    );
  }

  /// Reset "opened" messages back to queued (useful if app closed before sending).
  /// You can run this on app start.
  static Future<void> requeueOpenedMessages() async {
    final box = HiveService.outboundMessageBox();
    final opened = box.values
        .whereType<OutboundMessage>()
        .where((m) => m.status.trim().toLowerCase() == statusOpened);

    for (final m in opened) {
      m.status = statusQueued;
      await m.save();
    }
  }

  static Duration _backoffForAttempts(int attempts) {
    // 0 -> 0s, 1 -> 10s, 2 -> 30s, 3 -> 1m, 4 -> 3m, 5 -> 8m ...
    // capped at 30 minutes
    const base = [0, 10, 30, 60, 180, 480, 900, 1800];
    final idx = min(attempts, base.length - 1);
    return Duration(seconds: base[idx]);
  }

  static Future<bool> _openComposer(OutboundMessage msg) async {
    final channel = msg.channel.trim().toLowerCase();

    if (channel == 'whatsapp') {
      final phone = WhatsAppService.ugToE164(msg.toPhone);
      final err = await WhatsAppService.openChat(
        phoneE164: phone,
        message: msg.body,
      );
      return err == null;
    }

    if (channel == 'sms') {
      return _openSms(toPhone: msg.toPhone, body: msg.body);
    }

    return false;
  }

  static Future<bool> _openSms({
    required String toPhone,
    required String body,
  }) async {
    final phone = toPhone.trim();
    if (phone.isEmpty) return false;

    // sms:<number>?body=<text>
    final uri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: <String, String>{
        'body': body,
      },
    );

    final ok = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    return ok;
  }
}