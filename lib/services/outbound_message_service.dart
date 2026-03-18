import 'dart:math';

import '../models/outbound_message.dart';
import 'audit_service.dart';
import 'hive_service.dart';
import 'whatsapp_service.dart';
import 'sms_service.dart';

class OutboundMessageService {
  OutboundMessageService._();

  static String _id() => DateTime.now().millisecondsSinceEpoch.toString();

  // Status values (keep as strings for Hive simplicity)
  static const String statusQueued = 'queued';
  static const String statusOpened =
      'opened'; // opened in WhatsApp/SMS composer
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
      details:
          'Queued outbound message: channel=${msg.channel} to=${msg.toPhone}',
    );

    return msg;
  }

  // ---------------------------------------------------------------------------
  // F3: OTP delivery confirmation logging
  // ---------------------------------------------------------------------------
  /// Writes an audit entry confirming that an OTP outbound message was queued.
  /// Called immediately after [queue()] succeeds for an OTP SMS so there is an
  /// explicit, searchable audit trail separate from the generic OUTBOUND_MSG_QUEUED
  /// event. The entry records the message id, channel, phone, and initial status.
  static Future<void> logDeliveryAttempt({
    required OutboundMessage msg,
    required String propertyKey,
  }) async {
    await AuditService.log(
      action: 'OTP_DELIVERY_CONFIRMATION_LOGGED',
      propertyKey: propertyKey,
      details:
          'OTP delivery attempt logged: id=${msg.id} '
          'channel=${msg.channel} to=${msg.toPhone} '
          'status=${msg.status}',
    );
  }
  // ---------------------------------------------------------------------------

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

    final candidates = box.values.whereType<OutboundMessage>().where((m) {
      final st = (m.status).trim().toLowerCase();
      final ch = (m.channel).trim().toLowerCase();

      final allowedStatus = (st == statusQueued || st == statusFailed);
      if (!allowedStatus) return false;

      if (hasChannelFilter && ch != filterCh) return false;

      // Hard stop
      if (m.attempts >= maxAttempts) return false;

      // Backoff: if lastAttemptAt exists, wait before retry
      final wait = _backoffForAttempts(m.attempts);
      if (m.lastAttemptAt != null) {
        final dueAt = m.lastAttemptAt!.add(wait);
        if (now.isBefore(dueAt)) return false;
      }

      return true;
    }).toList();

    if (candidates.isEmpty) return null;

    // Oldest first (fair queue)
    candidates.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final msg = candidates.first;

    // Attempt opening
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
            'Opened composer id=${msg.id} channel=${msg.channel} to=${msg.toPhone} attempts=${msg.attempts}',
      );
      return msg;
    }

    // If open fails, don't immediately mark FAILED unless we are out of attempts.
    if (msg.attempts >= maxAttempts) {
      msg.status = statusFailed;
    } else {
      // Keep it queued so it can retry later after backoff
      msg.status = statusQueued;
    }

    await msg.save();

    await AuditService.log(
      action: 'OUTBOUND_MSG_OPEN_FAILED',
      propertyKey: msg.propertyKey,
      details:
          'Failed to open composer id=${msg.id} channel=${msg.channel} to=${msg.toPhone} attempts=${msg.attempts}',
    );

    return msg; // return msg so UI can show what happened
  }

  /// Mark message as SENT (call this from UI after user confirms it was sent).
  static Future<void> markSent(OutboundMessage msg) async {
    msg.status = statusSent;
    await msg.save();

    await AuditService.log(
      action: 'OUTBOUND_MSG_SENT',
      propertyKey: msg.propertyKey,
      details:
          'Marked sent: id=${msg.id} channel=${msg.channel} to=${msg.toPhone}',
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

  static Future<void> requeueOpenedMessages() async {
    final box = HiveService.outboundMessageBox();
    final now = DateTime.now();

    const staleAfter = Duration(minutes: 3);

    final opened = box.values.whereType<OutboundMessage>().where(
      (m) => m.status.trim().toLowerCase() == statusOpened,
    );

    for (final m in opened) {
      final openedAt = m.lastAttemptAt ?? m.createdAt;

      if (now.difference(openedAt) < staleAfter) continue;

      m.status = statusQueued;
      m.lastAttemptAt = now;

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

  static Future<OutboundMessage?> openSpecific(OutboundMessage msg) async {
    final now = DateTime.now();

    const minCooldown = Duration(seconds: 2);
    if (msg.lastAttemptAt != null &&
        now.difference(msg.lastAttemptAt!) < minCooldown) {
      return msg; // no-op, avoid inflating attempts instantly
    }

    // Hard stop
    if (msg.attempts >= maxAttempts) {
      msg.status = statusFailed;
      await msg.save();
      return msg;
    }

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
            'Opened composer (specific) id=${msg.id} channel=${msg.channel} to=${msg.toPhone} attempts=${msg.attempts}',
      );
      return msg;
    }

    // Same rule: only fail permanently when attempts exhausted.
    if (msg.attempts >= maxAttempts) {
      msg.status = statusFailed;
    } else {
      msg.status = statusQueued;
    }

    await msg.save();

    await AuditService.log(
      action: 'OUTBOUND_MSG_OPEN_FAILED',
      propertyKey: msg.propertyKey,
      details:
          'Failed to open composer (specific) id=${msg.id} channel=${msg.channel} to=${msg.toPhone} attempts=${msg.attempts}',
    );

    return msg;
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
      return SmsService.openSms(toPhone: msg.toPhone, body: msg.body);
    }

    return false;
  }
}
