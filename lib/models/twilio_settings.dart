import 'package:hive/hive.dart';
part 'twilio_settings.g.dart';

@HiveType(typeId: 12)
class TwilioSettings extends HiveObject {
  @HiveField(0)
  String accountSid;

  @HiveField(1)
  String authToken;

  @HiveField(2)
  String from;

  TwilioSettings({
    this.accountSid = '',
    this.authToken = '',
    this.from = '',
  });

  bool get isConfigured =>
      accountSid.trim().isNotEmpty &&
      authToken.trim().isNotEmpty &&
      from.trim().isNotEmpty;
}