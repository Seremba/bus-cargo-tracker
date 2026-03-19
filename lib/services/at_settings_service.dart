import 'package:hive/hive.dart';

import '../models/at_settings.dart';

class AtSettingsService {
  AtSettingsService._();

  static const String _boxName = 'at_settings';
  static const String _key = 'settings';

  static Box<AtSettings>? _box;

  static Future<void> init() async {
    if (!Hive.isBoxOpen(_boxName)) {
      _box = await Hive.openBox<AtSettings>(_boxName);
    } else {
      _box = Hive.box<AtSettings>(_boxName);
    }
  }

  static Box<AtSettings> _getBox() {
    if (_box != null && _box!.isOpen) return _box!;
    if (Hive.isBoxOpen(_boxName)) return Hive.box<AtSettings>(_boxName);
    throw StateError('AtSettings box not open. Call AtSettingsService.init()');
  }

  static AtSettings getOrCreate() {
    final box = _getBox();
    final existing = box.get(_key);
    if (existing != null) return existing;
    final defaults = AtSettings();
    box.put(_key, defaults);
    return defaults;
  }

  static Future<void> save(AtSettings s) async {
    final box = _getBox();
    await box.put(_key, s);
  }

  static bool get isConfigured {
    final s = getOrCreate();
    return s.apiKey.trim().isNotEmpty && s.username.trim().isNotEmpty;
  }
}
