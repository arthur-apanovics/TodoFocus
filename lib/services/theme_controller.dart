import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../theme/app_theme.dart';

/// Persists the user's theme choices — light/dark/system mode and the accent
/// colour — to the shared [app_settings] Hive box.
///
/// Hive deduplicates open boxes by name, so sharing [app_settings] with the
/// other settings services is safe.
class ThemeController extends ChangeNotifier {
  static const _boxName = 'app_settings';
  static const _modeKey = 'theme_mode';
  static const _colorKey = 'theme_color';

  final Box<String> _box;
  ThemeMode _mode;
  AppThemeColor _color;

  ThemeController._({
    required Box<String> box,
    required ThemeMode mode,
    required AppThemeColor color,
  })  : _box = box,
        _mode = mode,
        _color = color;

  /// Light / dark / follow-system. Defaults to [ThemeMode.system].
  ThemeMode get mode => _mode;

  /// The active accent colour. Defaults to [AppThemeColor.green].
  AppThemeColor get color => _color;

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    await _box.put(_modeKey, mode.name);
    notifyListeners();
  }

  Future<void> setColor(AppThemeColor color) async {
    if (color == _color) return;
    _color = color;
    await _box.put(_colorKey, color.name);
    notifyListeners();
  }

  static Future<ThemeController> init() async {
    final box = await Hive.openBox<String>(_boxName);
    return ThemeController._(
      box: box,
      mode: _parse(box.get(_modeKey), ThemeMode.values, ThemeMode.system),
      color:
          _parse(box.get(_colorKey), AppThemeColor.values, AppThemeColor.green),
    );
  }

  static T _parse<T extends Enum>(String? name, List<T> values, T fallback) {
    if (name == null) return fallback;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }
}
