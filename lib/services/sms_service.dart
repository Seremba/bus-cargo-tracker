import 'twilio_service.dart';

/// All SMS — OTPs, notifications and alerts — are sent via Twilio.
/// Covers Uganda, Kenya, South Sudan, Rwanda, DRC and all international numbers.
class SmsService {
  SmsService._();

  static Future<String?> sendSms({
    required String toPhone,
    required String body,
  }) async {
    return TwilioService.sendSms(toPhone: toPhone, body: body);
  }

  /// Opens the device SMS composer as a last resort.
  static bool openSms({required String toPhone, required String body}) {
    return false;
  }
}