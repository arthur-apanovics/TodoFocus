import 'package:flutter/material.dart';
import 'icon_catalog.dart';

/// Renders the icon stored in [Goal.emoji].
///
/// If [name] matches a catalog entry it renders a themed [Icon].
/// If [name] is a legacy Unicode emoji string it falls back to a [Text] widget
/// so old data is never silently lost.
/// If [name] is null, renders an empty [SizedBox].
class GoalSymbol extends StatelessWidget {
  final String? name;

  /// Explicit icon size. When null the widget inherits the ambient [IconTheme]
  /// size — matching the behaviour of a plain [Icon] widget and therefore
  /// staying in sync with any [_StatusBadge] rendered alongside it.
  final double? size;

  /// When null the widget uses the nearest [IconTheme] / [DefaultTextStyle]
  /// color, which follows the ambient theme automatically.
  final Color? color;

  const GoalSymbol({
    super.key,
    required this.name,
    this.size,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (name == null) return const SizedBox.shrink();

    final resolvedSize = size ?? IconTheme.of(context).size ?? 24.0;
    final iconData = iconDataForName(name!);
    if (iconData != null) {
      return Icon(
        iconData,
        size: resolvedSize,
        color: color ?? Theme.of(context).colorScheme.primary,
      );
    }

    // Legacy Unicode emoji — render as text so existing data is preserved.
    return Text(name!, style: TextStyle(fontSize: resolvedSize * 0.9));
  }
}
