import 'dart:math';

import '../models/outbound_message.dart';
import 'audit_service.dart';
import 'hive_service.dart';
import 'sms_service.dart';
import 'whatsapp_service.dart';

class OutboundMessageService {
  OutboundMessageService._();

  static String _id() => DateTime.now().millisecondsSinceEpoch.toString();

  static const String statusQueued = 'queued';
  static const String statusOpened = 'opened';
  static const String statusSent = 'sent';
  static const String statusFailed = 'failed';

  static const int maxAttempts = 6;

  static Future<OutboundMessage> queue({
    required String toPhone,
    required String body,
    String channel = 'sms',
    required String propertyKey,
  }) async {
    final box = HiveService.outboundMessageBox();

    final msg = OutboundMessage(
      id: _id(),
      toPhone: toPhone.trim(),
      channel: channel.trim().isEmpty ? 'sms' : channel.trim(),
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

    // For SMS: attempt automatic send immediately via Africa's Talking.
    // WhatsApp still requires manual open.
    if (msg.channel.trim().toLowerCase() == 'sms') {
      await _tryAutoSendSms(msg);
    }

    return msg;
  }

  static Future<void> _tryAutoSendSms(OutboundMessage msg) async {
    final err = await SmsService.sendSms(
      toPhone: msg.toPhone,
      body: msg.body,
    );

    msg.attempts = 1;
    msg.lastAttemptAt = DateTime.now();

    if (err == null) {
      msg.status = statusSent;
      await msg.save();
      await AuditService.log(
        action: 'OUTBOUND_MSG_SENT',
        propertyKey: msg.propertyKey,
        details:
            'Auto-sent SMS via Africa\'s Talking: id=${msg.id} to=${msg.toPhone}',
      );
    } else {
      msg.status = statusQueued;
      await msg.save();
      await AuditService.log(
        action: 'OUTBOUND_MSG_AUTO_SEND_FAILED',
        propertyKey: msg.propertyKey,
        details: 'Auto-send failed: $err — kept queued for retry.',
      );
    }
  }

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

  static Future<OutboundMessage?> processQueueOpenNext({
    String? channelFilter,
  }) async {
    final box = HiveService.outboundMessageBox();
    final now = DateTime.now();

    final filterCh = (channelFilter ?? '').trim().toLowerCase();
    final hasChannelFilter = filterCh.isNotEmpty;

    final candidates = box.values.whereType<OutboundMessage>().where((m) {
      final st = (m.status).trim().toLowerCase();
      final ch = (m.channel).trim().toLowerCase();
      if (!(st == statusQueued || st == statusFailed)) return false;
      if (hasChannelFilter && ch != filterCh) return false;
      if (m.attempts >= maxAttempts) return false;
      final wait = _backoffForAttempts(m.attempts);
      if (m.lastAttemptAt != null) {
        if (now.isBefore(m.lastAttemptAt!.add(wait))) return false;
      }
      return true;
    }).toList();

    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final msg = candidates.first;

    if (msg.channel.trim().toLowerCase() == 'sms') {
      await _tryAutoSendSms(msg);
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
        details: 'Opened composer id=${msg.id} channel=${msg.channel} '
            'to=${msg.toPhone} attempts=${msg.attempts}',
      );
      return msg;
    }

    msg.status = msg.attempts >= maxAttempts ? statusFailed : statusQueued;
    await msg.save();
    await AuditService.log(
      action: 'OUTBOUND_MSG_OPEN_FAILED',
      propertyKey: msg.propertyKey,
      details: 'Failed to open composer id=${msg.id} to=${msg.toPhone}',
    );
    return msg;
  }

  static Future<void> markSent(OutboundMessage msg) async {
    msg.status = statusSent;
    await msg.save();
    await AuditService.log(
      action: 'OUTBOUND_MSG_SENT',
      propertyKey: msg.propertyKey,
      details: 'Marked sent: id=${msg.id} to=${msg.toPhone}',
    );
  }

  static Future<void> markFailed(OutboundMessage msg, {String reason = ''}) async {
    msg.status = statusFailed;
    await msg.save();
    await AuditService.log(
      action: 'OUTBOUND_MSG_FAILED',
      propertyKey: msg.propertyKey,
      details: 'Marked failed: id=${msg.id} to=${msg.toPhone}. $reason',
    );
  }

  static Future<void> requeueOpenedMessages() async {
    final box = HiveService.outboundMessageBox();
    final now = DateTime.now();
    const staleAfter = Duration(minutes: 3);
    for (final m in box.values.whereType<OutboundMessage>()
        .where((m) => m.status.trim().toLowerCase() == statusOpened)) {
      final openedAt = m.lastAttemptAt ?? m.createdAt;
      if (now.difference(openedAt) < staleAfter) continue;
      m.status = statusQueued;
      m.lastAttemptAt = now;
      await m.save();
    }
  }

  static Duration _backoffForAttempts(int attempts) {
    const base = [0, 10, 30, 60, 180, 480, 900, 1800];
    final idx = min(attempts, base.length - 1);
    return Duration(seconds: base[idx]);
  }

  static Future<OutboundMessage?> openSpecific(OutboundMessage msg) async {
    final now = DateTime.now();
    const minCooldown = Duration(seconds: 2);
    if (msg.lastAttemptAt != null &&
        now.difference(msg.lastAttemptAt!) < minCooldown) { return msg; }
    if (msg.attempts >= maxAttempts) {
      msg.status = statusFailed;
      await msg.save();
      return msg;
    }

    if (msg.channel.trim().toLowerCase() == 'sms') {
      await _tryAutoSendSms(msg);
      return msg;
    }

    final ok = await _openComposer(msg);
    msg.attempts = msg.attempts + 1;
    msg.lastAttemptAt = now;
    if (ok) {
      msg.status = statusOpened;
      await msg.save();
      return msg;
    }
    msg.status = msg.attempts >= maxAttempts ? statusFailed : statusQueued;
    await msg.save();
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