import '../models/property.dart';
import '../models/property_status.dart';
import 'audit_service.dart';
import 'hive_service.dart';
import 'outbound_message_service.dart';
import 'session.dart';
import 'tracking_code_service.dart';

class ReceiverTrackingService {
  static const String _supportPhones = '+256 780 445860 / +256 766 799490';

  static String _cleanPhone(String raw) {
    // minimal cleanup; full E.164 can come later
    return raw.replaceAll(' ', '').trim();
  }

  static bool _looksLikePhone(String phone) {
    final p = _cleanPhone(phone);
    if (p.isEmpty) return false;
    if (p.length < 9) return false;
    // allow + and digits only
    return RegExp(r'^\+?\d+$').hasMatch(p);
  }

  static String _cleanChannel(String raw) {
    final c = (raw).trim().toLowerCase();
    if (c == 'sms') return 'sms';
    return 'whatsapp'; // default safe
  }

  static String _friendlyStatus(Property p) {
    // Repo semantics: LOADED is a milestone while still pending.
    switch (p.status) {
      case PropertyStatus.pending:
        return (p.loadedAt != null) ? 'LOADED' : 'PENDING';
      case PropertyStatus.inTransit:
        return 'IN TRANSIT';
      case PropertyStatus.delivered:
        return 'DELIVERED';
      case PropertyStatus.pickedUp:
        return 'PICKED UP';
    }
  }

  static Future afterPaymentRecorded({
    required Property property,
    required bool enabled,
    String channel = 'whatsapp', // whatsapp/sms
  }) async {
    final pBox = HiveService.propertyBox();
    final fresh = pBox.get(property.key) ?? property;

    final cleanChannel = _cleanChannel(channel);

    // If user didn't enable, don't spam audit logs.
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
        details:
            'Receiver phone invalid/missing. Could not enable tracking. Phone="$phone"',
      );
      return;
    }

    if (fresh.lastReceiverNotifiedAt != null) {
      final dt = DateTime.now()
          .difference(fresh.lastReceiverNotifiedAt!)
          .inSeconds;
      if (dt >= 0 && dt < 60) {
        return;
      }
    }

    // Enable and ensure tracking code
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

  /// Call this from PropertyService when status changes (inTransit/delivered/pickedUp).
  static Future notifyReceiverOnStatusChange({
    required Property property,
    required String eventLabel, // e.g. 'IN TRANSIT', 'DELIVERED'
    String channel =
        '', //  2B: if empty, use saved property.receiverNotifyChannel
  }) async {
    final pBox = HiveService.propertyBox();
    final fresh = pBox.get(property.key) ?? property;

    if (!fresh.notifyReceiver) return;

    final phone = _cleanPhone(fresh.receiverPhone);
    if (!_looksLikePhone(phone)) return;

    //  2B: choose effective channel from property if caller didn't specify
    final effective = channel.trim().isEmpty
        ? (fresh.receiverNotifyChannel.trim().isEmpty
              ? 'whatsapp'
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

  static String buildPaymentConfirmedMessage(Property p) {
    final code = p.trackingCode.trim().isEmpty ? '—' : p.trackingCode.trim();
    final cur = p.currency.trim().isEmpty ? 'UGX' : p.currency.trim();
    final route = p.routeName.trim().isEmpty ? '—' : p.routeName.trim();
    final when = DateTime.now().toLocal().toString().substring(0, 16);
    final status = _friendlyStatus(p);
    final desc = p.description.trim().isEmpty ? 'Cargo' : p.description.trim();

    return ''
        'Bebeto Cargo ✅ Payment confirmed\n'
        'Tracking: $code\n'
        'Item: $desc (x${p.itemCount})\n'
        'Amount: $cur ${p.amountPaidTotal}\n'
        'Route: $route | Dest: ${p.destination}\n'
        'Status: $status\n'
        'Time: $when\n'
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

    return ''
        'Bebeto Cargo update \n'
        'Tracking: $code\n'
        'Item: $desc (x${p.itemCount})\n'
        'Status: $eventLabel\n'
        'Route: $route | Dest: ${p.destination}\n'
        'Time: $when'
        '$pickupHint\n'
        'Help: $_supportPhones';
  }

  ///  NEW: partial-load message after trip starts.
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
              ? 'whatsapp'
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
      'Bebeto Cargo update ',
      'Tracking: $code',
      'Item: $desc (x${fresh.itemCount})',
      'In transit now: $loadedForTrip/$total item(s)',
      'Remaining at station: $remainingAtStation/$total',
      'Route: $route | Dest: ${fresh.destination}',
      'Time: $when',
      'Help: $_supportPhones',
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
          'Queued partial-load trip-start update to $phone. inTransit=$loadedForTrip/$total remaining=$remainingAtStation/$total',
    );
  }
}
