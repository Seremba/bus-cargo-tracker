import '../services/hive_service.dart';
import '../models/property.dart';

class TrackingCodeService {
  /// Deterministic 32-bit FNV-1a hash (stable across devices/sessions)
  static int _fnv1a32(String input) {
    const int fnvOffset = 0x811C9DC5;
    const int fnvPrime = 0x01000193;

    var hash = fnvOffset;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * fnvPrime) & 0xFFFFFFFF;
    }
    return hash & 0xFFFFFFFF;
  }

  static String generateFor(Property p) {
    final rawKey = (p.key ?? '').toString();

    // Prefer Hive key digits when available; otherwise fall back to createdAt ms
    final fallback = p.createdAt.millisecondsSinceEpoch.toString();
    final raw = rawKey.trim().isEmpty ? fallback : rawKey;

    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    final base = digits.isEmpty ? '000000' : digits;

    final last6 = base.length <= 6
        ? base.padLeft(6, '0')
        : base.substring(base.length - 6);

    // Deterministic hash seed
    final seed =
        '${p.receiverPhone}|${p.description}|${p.createdAt.toIso8601String()}';
    final h = _fnv1a32(seed);

    final a = String.fromCharCode(65 + (h % 26));
    final b = String.fromCharCode(65 + ((h ~/ 26) % 26));

    return 'BC-$last6-$a$b';
  }

  static bool isUnique(String code) {
    final c = code.trim();
    if (c.isEmpty) return false;
    final box = HiveService.propertyBox();
    return !box.values.any((p) => p.trackingCode.trim() == c);
  }

  static String ensureUnique(Property p) {
    var code = generateFor(p);

    if (!isUnique(code)) {
      // Try a deterministic suffix based on key/timestamp rather than random
      final t = DateTime.now().millisecondsSinceEpoch.toString();
      final last2 = t.substring(t.length - 2);
      code = '${code.substring(0, code.length - 2)}$last2';
    }

    if (!isUnique(code)) {
      // Final fallback: longer but guaranteed unique-ish offline
      code = 'BC-${DateTime.now().millisecondsSinceEpoch}-XX';
    }

    return code;
  }
}