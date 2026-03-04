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

  /// Friendly display (Uganda): show 07... if stored as 256...
  static String displayUg(String storedOrRaw) {
    final d = digitsOnly(storedOrRaw);
    if (d.startsWith('256') && d.length == 12) return '0${d.substring(3)}';
    return storedOrRaw.trim();
  }
}