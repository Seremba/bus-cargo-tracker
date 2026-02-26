import 'session.dart';
import 'package:hive/hive.dart';

import '../models/audit_event.dart';
import '../models/property.dart';
import '../models/notification_item.dart';
import '../models/trip.dart';
import '../models/user.dart';
import '../models/payment_record.dart';
import '../models/outbound_message.dart';
import '../models/property_item.dart';

class HiveService {
  static const String _propertyBoxName = 'properties';
  static const String _notificationBoxName = 'notifications';
  static const String _tripBoxName = 'trips';
  static const String _auditBoxName = 'audit_events';
  static const String _userBoxName = 'users';

  static const String _paymentBoxName = 'payments';
  static const String _printerSettingsBoxName = 'printer_settings';
  static const String _outboundMsgBoxName = 'outbound_messages';
  static const String _propertyItemBoxName = 'property_items';

  static void setUser(String userId) {
    Session.currentUserId = userId;
  }

  static Future<void> openAllBoxes() async {
    await openPropertyBox();
    await openPropertyItemBox();
    await openNotificationBox();
    await openTripBox();
    await openAuditBox();
    await openUserBox();
    await openPaymentBox();
    await openPrinterSettingsBox();
    await openOutboundMessageBox();
  }

  static Future<void> openPropertyBox() async {
    if (!Hive.isBoxOpen(_propertyBoxName)) {
      await Hive.openBox<Property>(_propertyBoxName);
    }
  }

  static Box<Property> propertyBox() {
    if (!Hive.isBoxOpen(_propertyBoxName)) {
      throw HiveError(
        'Property box is not open. Call HiveService.openPropertyBox() first.',
      );
    }
    return Hive.box<Property>(_propertyBoxName);
  }

  static Future<void> openPropertyItemBox() async {
    if (!Hive.isBoxOpen(_propertyItemBoxName)) {
      await Hive.openBox<PropertyItem>(_propertyItemBoxName);
    }
  }

  static Box<PropertyItem> propertyItemBox() {
    if (!Hive.isBoxOpen(_propertyItemBoxName)) {
      throw HiveError(
        'PropertyItem box is not open. Call HiveService.openPropertyItemBox() first.',
      );
    }
    return Hive.box<PropertyItem>(_propertyItemBoxName);
  }

  static Future<void> openNotificationBox() async {
    if (!Hive.isBoxOpen(_notificationBoxName)) {
      await Hive.openBox<NotificationItem>(_notificationBoxName);
    }
  }

  static Box<NotificationItem> notificationBox() {
    if (!Hive.isBoxOpen(_notificationBoxName)) {
      throw HiveError(
        'Notification box is not open. Call HiveService.openNotificationBox() first.',
      );
    }
    return Hive.box<NotificationItem>(_notificationBoxName);
  }

  static Future<void> openTripBox() async {
    if (!Hive.isBoxOpen(_tripBoxName)) {
      await Hive.openBox<Trip>(_tripBoxName);
    }
  }

  static Box<Trip> tripBox() {
    if (!Hive.isBoxOpen(_tripBoxName)) {
      throw HiveError(
        'Trip box is not open. Ensure main.dart opens it or call HiveService.openTripBox().',
      );
    }
    return Hive.box<Trip>(_tripBoxName);
  }

  static Future<void> openAuditBox() async {
    if (!Hive.isBoxOpen(_auditBoxName)) {
      await Hive.openBox<AuditEvent>(_auditBoxName);
    }
  }

  static Box<AuditEvent> auditBox() => Hive.box<AuditEvent>(_auditBoxName);

  static Future<void> openUserBox() async {
    if (!Hive.isBoxOpen(_userBoxName)) {
      await Hive.openBox<User>(_userBoxName);
    }
  }

  static Box<User> userBox() {
    if (!Hive.isBoxOpen(_userBoxName)) {
      throw HiveError(
        'User box is not open. Call HiveService.openUserBox() first.',
      );
    }
    return Hive.box<User>(_userBoxName);
  }

  static Future<void> openPaymentBox() async {
    if (!Hive.isBoxOpen(_paymentBoxName)) {
      await Hive.openBox<PaymentRecord>(_paymentBoxName);
    }
  }

  static Box<PaymentRecord> paymentBox() {
    if (!Hive.isBoxOpen(_paymentBoxName)) {
      throw HiveError(
        'Payment box is not open. Call HiveService.openPaymentBox() first.',
      );
    }
    return Hive.box<PaymentRecord>(_paymentBoxName);
  }

  static Future openPrinterSettingsBox() async {
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

  static Future<void> openOutboundMessageBox() async {
    if (!Hive.isBoxOpen(_outboundMsgBoxName)) {
      await Hive.openBox<OutboundMessage>(_outboundMsgBoxName);
    }
  }

  static Box<OutboundMessage> outboundMessageBox() {
    if (!Hive.isBoxOpen(_outboundMsgBoxName)) {
      throw HiveError(
        'OutboundMessage box is not open. Call HiveService.openOutboundMessageBox() first.',
      );
    }
    return Hive.box<OutboundMessage>(_outboundMsgBoxName);
  }

  static Future<void> closeAll() async {
    await Hive.close();
  }
}
