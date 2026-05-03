class PhoneNormalizer {
  static String digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9]'), '').trim();

  /// Canonical storage (digits only). We keep what user typed but cleaned.
  static String normalizeForStorage(String raw) => digitsOnly(raw);

  /// Message-ready phone for OTP/SMS/WhatsApp (Uganda-first).
  /// Returns '' if not safe to message.
  static String normalizeForMessaging(String raw) {
    var d = digitsOnly(raw);
    if (d.isEmpty) return '';

    // Uganda: 07XXXXXXXX -> 2567XXXXXXXX
    if (d.startsWith('0') && d.length == 10) {
      return '256${d.substring(1)}';
    }

    // Uganda: 7XXXXXXXX -> 2567XXXXXXXX
    if (!d.startsWith('256') && d.length == 9 && (d.startsWith('7') || d.startsWith('3'))) {
      return '256$d';
    }

    // International: assume already includes country code (E.164 digits length up to 15)
    if (!d.startsWith('0') && d.length >= 9 && d.length <= 15) {
      return d;
    }

    // Anything else is unsafe for messaging
    return '';
  }

  /// Converts any supported phone format to E.164 (+XXXXXXXXXXX).
  ///
  /// Returns null if the number cannot be safely converted.
  /// Used by TwilioService and TwilioVerifyService instead of
  /// maintaining their own private _toE164 methods.
  static String? toE164(String raw) {
    // normalizeForMessaging returns digits only — prepend + for E.164
    final normalized = normalizeForMessaging(raw);
    if (normalized.isNotEmpty) return '+$normalized';

    // Fallback for already-formatted E.164 strings with + prefix
    final p = raw.replaceAll(RegExp(r'[\s\-()]'), '');
    if (p.startsWith('+') && p.length >= 10 && p.length <= 16) return p;

    return null;
  }

  /// Friendly display (Uganda): show 07... if stored as 256...
  static String displayUg(String storedOrRaw) {
    final d = digitsOnly(storedOrRaw);
    if (d.startsWith('256') && d.length == 12) return '0${d.substring(3)}';
    return storedOrRaw.trim();
  }
}