class PropertyQrService {
  
  static String encodePropertyCode(String propertyCode) {
    final c = propertyCode.trim();
    return 'prop:$c';
  }

  /// Accepts either:
  /// - "prop:P-20260213-ABCD"
  /// - or raw "P-20260213-ABCD" (fallback)
  static String? decodeToPropertyCode(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;

    if (s.startsWith('prop:')) {
      final code = s.substring('prop:'.length).trim();
      return code.isEmpty ? null : code;
    }

    // fallback: if they scanned just the code
    return s;
  }
}
