import 'package:hive/hive.dart';

import 'session.dart';

import '../models/audit_event.dart';
import '../models/notification_item.dart';
import '../models/outbound_message.dart';
import '../models/payment_record.dart';
import '../models/property.dart';
import '../models/property_item.dart';
import '../models/trip.dart';
import '../models/user.dart';

import 'at_settings_service.dart';
import 'twilio_settings_service.dart';
import 'outbound_message_service.dart';
import '../models/sync_event.dart';

class HiveService {
  static const String _propertyBoxName = 'properties';
  static const String _propertyItemBoxName = 'property_items';
  static const String _notificationBoxName = 'notifications';
  static const String _tripBoxName = 'trips';
  static const String _auditBoxName = 'audit_events';
  static const String _userBoxName = 'users';
  static const String _paymentBoxName = 'payments';
  static const String _printerSettingsBoxName = 'printer_settings';
  static const String _outboundMsgBoxName = 'outbound_messages';
  static const String _passwordResetBoxName = 'password_resets';
  static const String _syncEventBoxName = 'sync_events';
  static const String _appSettingsBoxName = 'app_settings';

  static void setUser(String userId) {
    Session.currentUserId = userId;
  }

  static Future<void> openAllBoxes() async {
    await openAppSettingsBox();
    await AtSettingsService.init();       // AT SMS credentials
    TwilioSettingsService.getOrCreate();  // Twilio credentials (reads from appSettingsBox)

    await openPropertyBox();
    await openPropertyItemBox();
    await openNotificationBox();
    await openTripBox();
    await openAuditBox();
    await openUserBox();
    await openPaymentBox();
    await openPrinterSettingsBox();
    await openOutboundMessageBox();
    await openPasswordResetBox();
    await openSyncEventBox();

    await OutboundMessageService.requeueOpenedMessages();
  }

  // ── App settings ────────────────────────────────────────────────────────
  static Future<void> openAppSettingsBox() async {
    if (!Hive.isBoxOpen(_appSettingsBoxName)) {
      await Hive.openBox(_appSettingsBoxName);
    }
  }

  static Box appSettingsBox() {
    if (!Hive.isBoxOpen(_appSettingsBoxName)) {
      throw HiveError(
        'AppSettings box is not open. Call HiveService.openAppSettingsBox() first.',
      );
    }
    return Hive.box(_appSettingsBoxName);
  }

  // ── Properties ───────────────────────────────────────────────────────────
  static Future<void> openPropertyBox() async {
    if (!Hive.isBoxOpen(_propertyBoxName)) {
      await Hive.openBox<Property>(_propertyBoxName);
    }
  }

  static Box<Property> propertyBox() {
    if (!Hive.isBoxOpen(_propertyBoxName)) {
      throw HiveError(
        'Property box is not open.\nCall HiveService.openPropertyBox() first.',
      );
    }
    return Hive.box<Property>(_propertyBoxName);
  }

  // ── Property items ───────────────────────────────────────────────────────
  static Future<void> openPropertyItemBox() async {
    if (!Hive.isBoxOpen(_propertyItemBoxName)) {
      await Hive.openBox<PropertyItem>(_propertyItemBoxName);
    }
  }

  static Box<PropertyItem> propertyItemBox() {
    if (!Hive.isBoxOpen(_propertyItemBoxName)) {
      throw HiveError(
        'PropertyItem box is not open.\nCall HiveService.openPropertyItemBox() first.',
      );
    }
    return Hive.box<PropertyItem>(_propertyItemBoxName);
  }

  // ── Notifications ────────────────────────────────────────────────────────
  static Future<void> openNotificationBox() async {
    if (!Hive.isBoxOpen(_notificationBoxName)) {
      await Hive.openBox<NotificationItem>(_notificationBoxName);
    }
  }

  static Box<NotificationItem> notificationBox() {
    if (!Hive.isBoxOpen(_notificationBoxName)) {
      throw HiveError(
        'Notification box is not open.\nCall HiveService.openNotificationBox() first.',
      );
    }
    return Hive.box<NotificationItem>(_notificationBoxName);
  }

  // ── Trips ────────────────────────────────────────────────────────────────
  static Future<void> openTripBox() async {
    if (!Hive.isBoxOpen(_tripBoxName)) {
      await Hive.openBox<Trip>(_tripBoxName);
    }
  }

  static Box<Trip> tripBox() {
    if (!Hive.isBoxOpen(_tripBoxName)) {
      throw HiveError(
        'Trip box is not open.\nEnsure main.dart opens it or call HiveService.openTripBox().',
      );
    }
    return Hive.box<Trip>(_tripBoxName);
  }

  // ── Audit ────────────────────────────────────────────────────────────────
  static Future<void> openAuditBox() async {
    if (!Hive.isBoxOpen(_auditBoxName)) {
      await Hive.openBox<AuditEvent>(_auditBoxName);
    }
  }

  static Box<AuditEvent> auditBox() {
    if (!Hive.isBoxOpen(_auditBoxName)) {
      throw HiveError(
        'Audit box is not open.\nCall HiveService.openAuditBox() first.',
      );
    }
    return Hive.box<AuditEvent>(_auditBoxName);
  }

  // ── Users ────────────────────────────────────────────────────────────────
  static Future<void> openUserBox() async {
    if (!Hive.isBoxOpen(_userBoxName)) {
      await Hive.openBox<User>(_userBoxName);
    }
  }

  static Box<User> userBox() {
    if (!Hive.isBoxOpen(_userBoxName)) {
      throw HiveError(
        'User box is not open.\nCall HiveService.openUserBox() first.',
      );
    }
    return Hive.box<User>(_userBoxName);
  }

  // ── Payments ─────────────────────────────────────────────────────────────
  static Future<void> openPaymentBox() async {
    if (!Hive.isBoxOpen(_paymentBoxName)) {
      await Hive.openBox<PaymentRecord>(_paymentBoxName);
    }
  }

  static Box<PaymentRecord> paymentBox() {
    if (!Hive.isBoxOpen(_paymentBoxName)) {
      throw HiveError(
        'Payment box is not open.\nCall HiveService.openPaymentBox() first.',
      );
    }
    return Hive.box<PaymentRecord>(_paymentBoxName);
  }

  // ── Printer settings ─────────────────────────────────────────────────────
  static Future<void> openPrinterSettingsBox() async {
    if (!Hive.isBoxOpen(_printerSettingsBoxName)) {
      await Hive.openBox(_printerSettingsBoxName);
    }
  }

  static Box printerSettingsBox() {
    if (!Hive.isBoxOpen(_printerSettingsBoxName)) {
      throw HiveError(
        'PrinterSettings box is not open.\nCall HiveService.openPrinterSettingsBox() first.',
      );
    }
    return Hive.box(_printerSettingsBoxName);
  }

  // ── Outbound messages ────────────────────────────────────────────────────
  static Future<void> openOutboundMessageBox() async {
    if (!Hive.isBoxOpen(_outboundMsgBoxName)) {
      await Hive.openBox<OutboundMessage>(_outboundMsgBoxName);
    }
  }

  static Box<OutboundMessage> outboundMessageBox() {
    if (!Hive.isBoxOpen(_outboundMsgBoxName)) {
      throw HiveError(
        'OutboundMessage box is not open.\nCall HiveService.openOutboundMessageBox() first.',
      );
    }
    return Hive.box<OutboundMessage>(_outboundMsgBoxName);
  }

  // ── Password resets ──────────────────────────────────────────────────────
  static Future openPasswordResetBox() async {
    if (!Hive.isBoxOpen(_passwordResetBoxName)) {
      await Hive.openBox(_passwordResetBoxName);
    }
  }

  static Box passwordResetBox() {
    if (!Hive.isBoxOpen(_passwordResetBoxName)) {
      throw HiveError(
        'PasswordReset box is not open.\nCall HiveService.openPasswordResetBox() first.',
      );
    }
    return Hive.box(_passwordResetBoxName);
  }

  // ── Sync events ──────────────────────────────────────────────────────────
  static Future<void> openSyncEventBox() async {
    if (!Hive.isBoxOpen(_syncEventBoxName)) {
      await Hive.openBox<SyncEvent>(_syncEventBoxName);
    }
  }

  static Box<SyncEvent> syncEventBox() {
    if (!Hive.isBoxOpen(_syncEventBoxName)) {
      throw HiveError(
        'SyncEvent box is not open.\nCall HiveService.openSyncEventBox() first.',
      );
    }
    return Hive.box<SyncEvent>(_syncEventBoxName);
  }

  static Future<void> closeAll() async {
    await Hive.close();
  }
}