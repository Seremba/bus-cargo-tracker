import 'package:url_launcher/url_launcher.dart';

class WhatsAppService {
  /// Opens WhatsApp with a prefilled message.
  /// Returns true if launch was successful.
  static Future<bool> openChat({
    required String phoneE164, // e.g. +2567xxxxxxx
    required String message,
  }) async {
    final normalized = _normalizeE164(phoneE164);
    if (normalized.isEmpty) return false;

    final encoded = Uri.encodeComponent(message);

    // WhatsApp deep links:
    // Android prefers wa.me, iOS also works with wa.me.
    final uri = Uri.parse('https://wa.me/$normalized?text=$encoded');

    if (!await canLaunchUrl(uri)) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Convert "+256..." to "256..." for wa.me
  static String _normalizeE164(String phone) {
    var p = phone.trim();
    if (p.isEmpty) return '';
    // keep digits + leading +
    p = p.replaceAll(RegExp(r'[^0-9\+]'), '');
    if (p.startsWith('+')) p = p.substring(1);
    // wa.me wants digits only
    p = p.replaceAll(RegExp(r'[^0-9]'), '');
    return p;
  }

  /// Uganda-friendly normalizer if you store "07..." numbers
  /// You can call this before openChat if needed.
  static String ugToE164(String phone) {
    var p = phone.trim().replaceAll(RegExp(r'[^0-9\+]'), '');
    if (p.startsWith('+')) return p;

    // if "07xxxxxxxx"
    if (p.startsWith('0') && p.length >= 10) {
      return '+256${p.substring(1)}';
    }

    // if already "2567..."
    if (p.startsWith('256')) return '+$p';

    return p; // fallback
  }

  static bool isProbablySmartPhoneUser(String phone) {
    // Basic assumption: if the phone exists, allow WhatsApp option.
    // Later you can add a user preference flag.
    return phone.trim().isNotEmpty;
  }
}
