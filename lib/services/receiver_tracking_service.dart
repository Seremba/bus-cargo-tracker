import '../models/property.dart';
import '../models/property_status.dart';
import 'audit_service.dart';
import 'hive_service.dart';
import 'outbound_message_service.dart';
import 'property_service.dart';
import 'session.dart';
import 'tracking_code_service.dart';

class ReceiverTrackingService {
  static const String _supportPhones = '+256 780 445860 / +256 766 799490';

  static String _cleanPhone(String raw) => raw.replaceAll(' ', '').trim();

  static bool _looksLikePhone(String phone) {
    final p = _cleanPhone(phone);
    if (p.isEmpty || p.length < 9) return false;
    return RegExp(r'^\+?\d+$').hasMatch(p);
  }

  // Default channel is sms — safest for receivers without smartphones.
  // WhatsApp is only used when explicitly set to 'whatsapp'.
  static String _cleanChannel(String raw) {
    final c = raw.trim().toLowerCase();
    return c == 'whatsapp' ? 'whatsapp' : 'sms';
  }

  static String _friendlyStatus(Property p) {
    switch (p.status) {
      case PropertyStatus.pending:
        return 'PENDING';
      case PropertyStatus.loaded:
        return 'LOADED';
      case PropertyStatus.inTransit:
        return 'IN TRANSIT';
      case PropertyStatus.delivered:
        return 'DELIVERED';
      case PropertyStatus.pickedUp:
        return 'PICKED UP';
      case PropertyStatus.rejected:
        return 'REJECTED';
      case PropertyStatus.expired:
        return 'EXPIRED';
      case PropertyStatus.underReview:
        return 'UNDER REVIEW';
    }
  }

  // ── Called by DeskRecordPaymentScreen after payment ──────────────────────
  static Future afterPaymentRecorded({
    required Property property,
    required bool enabled,
    String channel = 'sms',
  }) async {
    final pBox = HiveService.propertyBox();
    final fresh = pBox.get(property.key) ?? property;
    final cleanChannel = _cleanChannel(channel);

    if (!enabled) {
      if (fresh.notifyReceiver == true) {
        fresh.notifyReceiver = false;
        await fresh.save();
        await AuditService.log(
          action: 'RECEIVER_TRACKING_DISABLED',
          propertyKey: fresh.key.toString(),
          details: 'Disabled receiver progress updates after payment.',
        );
      }
      return;
    }

    final phone = _cleanPhone(fresh.receiverPhone);
    if (!_looksLikePhone(phone)) {
      await AuditService.log(
        action: 'RECEIVER_TRACKING_ENABLE_FAILED',
        propertyKey: fresh.key.toString(),
        details: 'Receiver phone invalid/missing. Phone="$phone"',
      );
      return;
    }

    if (fresh.lastReceiverNotifiedAt != null) {
      final dt = DateTime.now()
          .difference(fresh.lastReceiverNotifiedAt!)
          .inSeconds;
      if (dt >= 0 && dt < 60) return;
    }

    if (fresh.trackingCode.trim().isEmpty) {
      fresh.trackingCode = TrackingCodeService.ensureUnique(fresh);
    }

    fresh.notifyReceiver = true;
    fresh.receiverNotifyEnabledAt = DateTime.now();
    fresh.receiverNotifyEnabledByUserId = (Session.currentUserId ?? '').trim();
    fresh.receiverNotifyChannel = cleanChannel;
    await fresh.save();

    await AuditService.log(
      action: 'RECEIVER_TRACKING_ENABLED',
      propertyKey: fresh.key.toString(),
      details:
          'Enabled receiver updates. TrackingCode=${fresh.trackingCode}. Channel=$cleanChannel',
    );

    final body = buildPaymentConfirmedMessage(fresh);
    await OutboundMessageService.queue(
      toPhone: phone,
      channel: cleanChannel,
      body: body,
      propertyKey: fresh.key.toString(),
    );

    fresh.lastReceiverNotifiedAt = DateTime.now();
    await fresh.save();

    await AuditService.log(
      action: 'RECEIVER_NOTIFY_QUEUED',
      propertyKey: fresh.key.toString(),
      details: 'Queued payment-confirmed receiver message to $phone.',
    );
  }

  // ── Called by StaffStationScreen when staff taps Mark Delivered ──────────
  // Sends a delivery notification AND the OTP in the same message for SMS
  // users (no smartphone = they need the OTP in the SMS itself).
  // WhatsApp users get a standard delivery update; admin sends OTP separately.
  static Future afterDelivered({required Property property}) async {
    final pBox = HiveService.propertyBox();
    final fresh = pBox.get(property.key) ?? property;

    if (!fresh.notifyReceiver) return;

    final phone = _cleanPhone(fresh.receiverPhone);
    if (!_looksLikePhone(phone)) return;

    final channel = _cleanChannel(
      fresh.receiverNotifyChannel.trim().isEmpty
          ? 'sms'
          : fresh.receiverNotifyChannel,
    );

    if (fresh.trackingCode.trim().isEmpty) {
      fresh.trackingCode = TrackingCodeService.ensureUnique(fresh);
      await fresh.save();
    }

    // For SMS channel: generate/refresh OTP and include it in the message
    // so the receiver gets everything they need in one SMS.
    // For WhatsApp: send standard delivery update; OTP sent separately by admin.
    String body;
    if (channel == 'sms') {
      // Generate a fresh OTP for delivery notification
      final otpPlaintext = await PropertyService.adminResetOtp(fresh);
      body = buildDeliveredWithOtpMessage(fresh, otpPlaintext: otpPlaintext);
    } else {
      body = buildStatusUpdateMessage(fresh, eventLabel: 'DELIVERED');
    }

    await OutboundMessageService.queue(
      toPhone: phone,
      channel: channel,
      body: body,
      propertyKey: fresh.key.toString(),
    );

    fresh.lastReceiverNotifiedAt = DateTime.now();
    await fresh.save();

    await AuditService.log(
      action: 'RECEIVER_NOTIFY_QUEUED',
      propertyKey: fresh.key.toString(),
      details:
          'Queued delivered notification to $phone via $channel '
          '(OTP included: ${channel == 'sms'}).',
    );
  }

  // ── Called by StaffStationScreen Resend SMS button ───────────────────────
  // Re-queues the OTP SMS without exposing plaintext to staff.
  // Generates a fresh OTP, encodes it in the message, queues it.
  static Future resendPickupOtpSms(Property property) async {
    final pBox = HiveService.propertyBox();
    final fresh = pBox.get(property.key) ?? property;

    final phone = _cleanPhone(fresh.receiverPhone);
    if (!_looksLikePhone(phone)) {
      throw Exception('Receiver phone missing or invalid');
    }

    // Always send as SMS — this method is specifically for non-smartphone users
    const channel = 'sms';

    final otpPlaintext = await PropertyService.adminResetOtp(fresh);
    if (otpPlaintext == null) {
      throw Exception('Could not generate OTP');
    }

    final refetched = pBox.get(property.key) ?? fresh;
    final body = buildDeliveredWithOtpMessage(
      refetched,
      otpPlaintext: otpPlaintext,
    );

    await OutboundMessageService.queue(
      toPhone: phone,
      channel: channel,
      body: body,
      propertyKey: fresh.key.toString(),
    );

    await AuditService.log(
      action: 'RECEIVER_OTP_SMS_RESENT',
      propertyKey: fresh.key.toString(),
      details: 'OTP SMS re-queued to $phone by staff/admin.',
    );
  }

  static Future notifyReceiverOnStatusChange({
    required Property property,
    required String eventLabel,
    String channel = '',
  }) async {
    final pBox = HiveService.propertyBox();
    final fresh = pBox.get(property.key) ?? property;

    if (!fresh.notifyReceiver) return;

    final phone = _cleanPhone(fresh.receiverPhone);
    if (!_looksLikePhone(phone)) return;

    final effective = channel.trim().isEmpty
        ? (fresh.receiverNotifyChannel.trim().isEmpty
              ? 'sms'
              : fresh.receiverNotifyChannel)
        : channel;

    final cleanChannel = _cleanChannel(effective);

    final critical = (eventLabel == 'DELIVERED' || eventLabel == 'PICKED UP');
    if (!critical && fresh.lastReceiverNotifiedAt != null) {
      final dt = DateTime.now()
          .difference(fresh.lastReceiverNotifiedAt!)
          .inSeconds;
      if (dt < 180) return;
    }

    if (fresh.trackingCode.trim().isEmpty) {
      fresh.trackingCode = TrackingCodeService.ensureUnique(fresh);
      await fresh.save();
    }

    final body = buildStatusUpdateMessage(fresh, eventLabel: eventLabel);
    await OutboundMessageService.queue(
      toPhone: phone,
      channel: cleanChannel,
      body: body,
      propertyKey: fresh.key.toString(),
    );

    fresh.lastReceiverNotifiedAt = DateTime.now();
    await fresh.save();

    await AuditService.log(
      action: 'RECEIVER_NOTIFY_QUEUED',
      propertyKey: fresh.key.toString(),
      details: 'Queued status update ($eventLabel) to $phone.',
    );
  }

  static Future notifyReceiverPartialLoadOnTripStart({
    required Property property,
    required int loadedForTrip,
    required int total,
    required int remainingAtStation,
    required String routeName,
    String channel = '',
  }) async {
    final pBox = HiveService.propertyBox();
    final fresh = pBox.get(property.key) ?? property;

    if (!fresh.notifyReceiver) return;

    final phone = _cleanPhone(fresh.receiverPhone);
    if (!_looksLikePhone(phone)) return;

    final effective = channel.trim().isEmpty
        ? (fresh.receiverNotifyChannel.trim().isEmpty
              ? 'sms'
              : fresh.receiverNotifyChannel)
        : channel;

    final cleanChannel = _cleanChannel(effective);

    if (fresh.lastReceiverNotifiedAt != null) {
      final dt = DateTime.now()
          .difference(fresh.lastReceiverNotifiedAt!)
          .inSeconds;
      if (dt < 180) return;
    }

    if (fresh.trackingCode.trim().isEmpty) {
      fresh.trackingCode = TrackingCodeService.ensureUnique(fresh);
      await fresh.save();
    }

    final code = fresh.trackingCode.trim();
    final when = DateTime.now().toLocal().toString().substring(0, 16);
    final desc = fresh.description.trim().isEmpty
        ? 'Cargo'
        : fresh.description.trim();
    final route = routeName.trim().isEmpty
        ? (fresh.routeName.trim().isEmpty ? '—' : fresh.routeName.trim())
        : routeName.trim();

    final body = [
      'UNEX LOGISTICS',
      '',
      'Tracking: $code',
      'Item: $desc (x${fresh.itemCount})',
      '',
      '$loadedForTrip of $total item(s) have departed via $route.',
      if (remainingAtStation > 0)
        '$remainingAtStation item(s) remain at the station and will follow on the next trip.',
      '',
      'Destination: ${fresh.destination}',
      'Time: $when',
      '',
      'Support: $_supportPhones',
    ].join('\n');

    await OutboundMessageService.queue(
      toPhone: phone,
      channel: cleanChannel,
      body: body,
      propertyKey: fresh.key.toString(),
    );

    fresh.lastReceiverNotifiedAt = DateTime.now();
    await fresh.save();

    await AuditService.log(
      action: 'RECEIVER_NOTIFY_QUEUED',
      propertyKey: fresh.key.toString(),
      details:
          'Queued partial-load trip-start update to $phone. '
          'inTransit=$loadedForTrip/$total remaining=$remainingAtStation/$total',
    );
  }

  // ── Message builders ──────────────────────────────────────────────────────

  static String buildPaymentConfirmedMessage(Property p) {
    final code = p.trackingCode.trim().isEmpty ? '—' : p.trackingCode.trim();
    final cur = p.currency.trim().isEmpty ? 'UGX' : p.currency.trim();
    final route = p.routeName.trim().isEmpty ? '—' : p.routeName.trim();
    final when = DateTime.now().toLocal().toString().substring(0, 16);
    final status = _friendlyStatus(p);
    final desc = p.description.trim().isEmpty ? 'Cargo' : p.description.trim();

    return 'UNEX LOGISTICS ✅ Payment confirmed\n'
        'Tracking: $code\n'
        'Item: $desc (x${p.itemCount})\n'
        'Amount: $cur ${p.amountPaidTotal}\n'
        'Route: $route | Dest: ${p.destination}\n'
        'Status: $status\n'
        'Time: $when\n'
        'Track: unex://track/$code\n'
        'Help: $_supportPhones';
  }

  static String buildStatusUpdateMessage(
    Property p, {
    required String eventLabel,
  }) {
    final code = p.trackingCode.trim().isEmpty ? '—' : p.trackingCode.trim();
    final route = p.routeName.trim().isEmpty ? '—' : p.routeName.trim();
    final when = DateTime.now().toLocal().toString().substring(0, 16);
    final desc = p.description.trim().isEmpty ? 'Cargo' : p.description.trim();
    final pickupHint = (eventLabel == 'DELIVERED')
        ? '\nPickup requires: OTP + QR'
        : '';

    return 'UNEX LOGISTICS update \n'
        'Tracking: $code\n'
        'Item: $desc (x${p.itemCount})\n'
        'Status: $eventLabel\n'
        'Route: $route | Dest: ${p.destination}\n'
        'Time: $when'
        '$pickupHint\n'
        'Track: unex://track/$code\n'
        'Help: $_supportPhones';
  }

  // SMS-specific delivery message that includes the OTP inline.
  // Used for receivers without smartphones who cannot use WhatsApp.
  static String buildDeliveredWithOtpMessage(
    Property p, {
    required String? otpPlaintext,
  }) {
    final code = p.trackingCode.trim().isEmpty ? '—' : p.trackingCode.trim();
    final route = p.routeName.trim().isEmpty ? '—' : p.routeName.trim();
    final when = DateTime.now().toLocal().toString().substring(0, 16);
    final desc = p.description.trim().isEmpty ? 'Cargo' : p.description.trim();
    final otpLine = (otpPlaintext != null && otpPlaintext.isNotEmpty)
        ? '\nPickup OTP: $otpPlaintext'
        : '\nPickup OTP: (contact station)';

    return 'UNEX LOGISTICS: Your cargo has arrived ✅\n'
        'Tracking: $code\n'
        'Item: $desc (x${p.itemCount})\n'
        'Route: $route | Dest: ${p.destination}\n'
        'Time: $when'
        '$otpLine\n'
        'Show this SMS + OTP at ${p.destination} station to collect.\n'
        'Track: unex://track/$code\n'
        'Help: $_supportPhones';
  }
}