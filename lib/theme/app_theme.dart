import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_palette.dart';

/// Selectable accent colours. The seed drives Material 3's generated
/// [ColorScheme]; the rest of the [AppPalette] is derived from it.
enum AppThemeColor {
  green(kBrandColor, 'Forest'),
  teal(Color(0xFF00897B), 'Teal'),
  indigo(Color(0xFF3F51B5), 'Indigo'),
  ocean(Color(0xFF1976D2), 'Ocean'),
  amber(Color(0xFFEF6C00), 'Amber'),
  rose(Color(0xFFC2185B), 'Rose');

  const AppThemeColor(this.seed, this.displayName);

  /// Seed colour fed to [ColorScheme.fromSeed].
  final Color seed;

  /// Human-readable label shown in the settings picker.
  final String displayName;
}

/// Builds the light and dark [ThemeData] for a chosen [AppThemeColor].
///
/// Every theme carries an [AppPalette] extension so screens can read the
/// app's semantic colours without hard-coding light-mode greys.
class AppTheme {
  AppTheme._();

  static ThemeData light(AppThemeColor color) =>
      _build(color, Brightness.light);

  static ThemeData dark(AppThemeColor color) => _build(color, Brightness.dark);

  static ThemeData _build(AppThemeColor color, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: color.seed,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      extensions: [AppPalette.from(scheme)],
    );
  }
}
