import 'package:flutter/material.dart';

/// Semantic colours that Material's [ColorScheme] doesn't cover, resolved
/// per brightness so the app reads correctly in both light and dark mode.
///
/// Attached to [ThemeData.extensions] by `AppTheme`; read at call sites via
/// the [AppPaletteX.palette] extension on [BuildContext].
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  /// Primary highlight — focused goals, the current step, active CTAs.
  final Color accent;

  /// Secondary text, inactive chrome, hint text, empty-state copy.
  final Color muted;

  /// High-emphasis monotone — e.g. the hollow circle on the current step.
  final Color strong;

  /// The drag-handle pill at the top of bottom sheets.
  final Color sheetHandle;

  /// Completion / success indicators.
  final Color success;

  /// Subtle tint pairing with [success] — chip and badge backgrounds.
  final Color successSurface;

  /// Destructive actions — delete buttons, clear-data confirmations.
  final Color destructive;

  /// Foreground colour on top of [destructive].
  final Color onDestructive;

  const AppPalette({
    required this.accent,
    required this.muted,
    required this.strong,
    required this.sheetHandle,
    required this.success,
    required this.successSurface,
    required this.destructive,
    required this.onDestructive,
  });

  /// Derives the palette from a Material [ColorScheme] so the monotone scale
  /// and surface tints track the active brightness automatically.
  factory AppPalette.from(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    final success = isDark ? Colors.green.shade400 : Colors.green.shade700;
    return AppPalette(
      accent: scheme.primary,
      muted: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
      strong: isDark ? Colors.grey.shade300 : Colors.grey.shade800,
      sheetHandle: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
      success: success,
      successSurface: Color.alphaBlend(
        success.withValues(alpha: isDark ? 0.22 : 0.14),
        scheme.surface,
      ),
      destructive: isDark ? Colors.red.shade400 : Colors.red.shade600,
      onDestructive: Colors.white,
    );
  }

  @override
  AppPalette copyWith({
    Color? accent,
    Color? muted,
    Color? strong,
    Color? sheetHandle,
    Color? success,
    Color? successSurface,
    Color? destructive,
    Color? onDestructive,
  }) {
    return AppPalette(
      accent: accent ?? this.accent,
      muted: muted ?? this.muted,
      strong: strong ?? this.strong,
      sheetHandle: sheetHandle ?? this.sheetHandle,
      success: success ?? this.success,
      successSurface: successSurface ?? this.successSurface,
      destructive: destructive ?? this.destructive,
      onDestructive: onDestructive ?? this.onDestructive,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      accent: Color.lerp(accent, other.accent, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      strong: Color.lerp(strong, other.strong, t)!,
      sheetHandle: Color.lerp(sheetHandle, other.sheetHandle, t)!,
      success: Color.lerp(success, other.success, t)!,
      successSurface: Color.lerp(successSurface, other.successSurface, t)!,
      destructive: Color.lerp(destructive, other.destructive, t)!,
      onDestructive: Color.lerp(onDestructive, other.onDestructive, t)!,
    );
  }
}

extension AppPaletteX on BuildContext {
  /// The app's semantic colour palette for the active theme.
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}
