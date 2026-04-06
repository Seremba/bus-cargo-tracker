import 'africas_talking_service.dart';
import 'twilio_service.dart';

/// SMS routing service.
///
/// TEMPORARY: All SMS routed through Twilio while Africa's Talking
/// account activation is pending. Restore smart routing once AT is
/// fully activated by uncommenting the routing logic below.
///
/// Smart routing (restore later):
///   Uganda numbers (+256) → Africa's Talking (cheaper, local)
///   International numbers → Twilio (reliable global coverage)
///   If primary fails → fallback to other provider automatically
class SmsService {
  SmsService._();

  static Future<String?> sendSms({
    required String toPhone,
    required String body,
  }) async {
    // TEMPORARY: force all SMS through Twilio during testing
    // Remove this and uncomment the routing block below once AT is activated
    return TwilioService.sendSms(toPhone: toPhone, body: body);

    // ── Smart routing (restore after AT activation) ──────────────────────
    // final isUganda = TwilioService.isUgandaNumber(toPhone);
    // if (isUganda) {
    //   final atError = await AfricasTalkingService.sendSms(
    //     toPhone: toPhone,
    //     body: body,
    //   );
    //   if (atError == null) return null;
    //   print('[SmsService] AT failed for Uganda number, falling back to Twilio: $atError');
    //   return TwilioService.sendSms(toPhone: toPhone, body: body);
    // } else {
    //   final twilioError = await TwilioService.sendSms(
    //     toPhone: toPhone,
    //     body: body,
    //   );
    //   if (twilioError == null) return null;
    //   print('[SmsService] Twilio failed for international number, falling back to AT: $twilioError');
    //   return AfricasTalkingService.sendSms(toPhone: toPhone, body: body);
    // }
  }

  /// Opens the device SMS composer as a last resort.
  static bool openSms({required String toPhone, required String body}) {
    // Not implemented — SMS composer removed in favour of API-only sending
    return false;
  }
}
