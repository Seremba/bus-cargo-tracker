import '../models/property.dart';
import 'hive_service.dart';

class PropertyLookupService {
  static String _norm(String s) => s.trim().toUpperCase();

  static Property? findByPropertyCode(String code) {
    final c = _norm(code);
    if (c.isEmpty) return null;

    final box = HiveService.propertyBox();

    try {
      return box.values.firstWhere(
        (p) => _norm(p.propertyCode) == c,
      );
    } catch (_) {
      return null;
    }
  }
}
