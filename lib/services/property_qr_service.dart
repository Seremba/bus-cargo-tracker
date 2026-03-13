class PropertyQrService {
  static String encodePropertyCode(String propertyCode) {
    final c = propertyCode.trim();
    return 'prop:$c';
  }

  static String? decodeToPropertyCode(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;

    if (s.toLowerCase().startsWith('prop:')) {
      final code = s.substring(5).trim();
      return code.isEmpty ? null : code;
    }

    return s;
  }
}