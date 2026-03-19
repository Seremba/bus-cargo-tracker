import 'package:hive/hive.dart';

part 'at_settings.g.dart';

@HiveType(typeId: 11)
class AtSettings extends HiveObject {
  @HiveField(0)
  String apiKey;

  @HiveField(1)
  String username;

  @HiveField(2)
  bool isSandbox;

  /// Alphanumeric sender ID shown on receiver's phone (max 11 chars).
  /// Leave empty to use Africa's Talking default shortcode.
  @HiveField(3)
  String senderId;

  AtSettings({
    this.apiKey = '',
    this.username = 'sandbox',
    this.isSandbox = true,
    this.senderId = 'UNExLogstx',
  });
}