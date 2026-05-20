import 'package:flutter/material.dart';

/// Central colour palette for the app.
///
/// Tweak the values here to experiment with the visual identity. Every
/// screen pulls its colours from this class, so changes propagate
/// everywhere without touching individual widgets.
///
/// Naming convention is semantic, not visual — the variable name describes
/// the *role* the colour plays, not its hue. That way you can swap
/// `accent` from indigo to teal (or grey, for a strict monotone look)
/// without renaming anything.
class AppColors {
  // Private constructor — this class is a namespace for static fields,
  // never instantiated.
  AppColors._();

  // ---------------------------------------------------------------------
  // Monotone scale
  //
  // Used for state indicators inside lists. Three steps is the maximum
  // most designs can read at a glance — more steps blur into each other.
  // ---------------------------------------------------------------------

  /// Faded out — completed rows, finished states, "done and forgotten".
  static final Color faded = Colors.grey.shade400;

  /// Muted — secondary actions and inactive-but-present chrome
  /// (lock icons, undo/restore buttons, hint text, empty states).
  static final Color muted = Colors.grey.shade600;

  /// Strong — the primary call-to-action in monotone form
  /// (e.g. the hollow circle on the current subtask).
  static final Color strong = Colors.grey.shade800;

  // ---------------------------------------------------------------------
  // Surface chrome
  // ---------------------------------------------------------------------

  /// The drag handle pill at the top of bottom sheets.
  /// Lighter than `faded` because it's purely decorative.
  static final Color sheetHandle = Colors.grey.shade300;

  // ---------------------------------------------------------------------
  // Semantic accents
  //
  // These are the variables to change when experimenting with the
  // visual identity. Each accent has a paired "surface" variant — a
  // light tint suitable for backgrounds (progress badges, chips, etc.).
  // ---------------------------------------------------------------------

  /// Primary highlight — focused goals, the "current" step, active CTAs.
  /// Material Green 800 — the deeper "focus here" tone, intentionally distinct
  /// from `success` so the eye doesn't read "active" and "done" as the same
  /// state.
  static final Color accent = Colors.green.shade800;
  static final Color accentSurface = Colors.indigo.shade50;

  /// Completion / success — all-done indicators, completed-state badges.
  /// Material Green 500 — the brighter "you did it" tone. Kept inside the
  /// green family for brand restraint but visibly lighter than `accent`.
  static const Color success = Colors.green;
  static final Color successSurface = Colors.green.shade50;

  // ---------------------------------------------------------------------
  // Destructive
  //
  // Deliberately not folded into the monotone scale — destructive actions
  // earn their own warning hue. Override here if you want to soften it.
  // ---------------------------------------------------------------------

  static const Color destructive = Colors.red;
  static const Color onDestructive = Colors.white;
}

/// Bottom padding that scrollable lists should apply so their final item can
/// be scrolled clear of a floating action button (Material's extended FAB is
/// ~48 dp tall, plus a 16 dp screen margin, plus slack for fat-finger taps).
///
/// Acts as the "ghost entry" the user asked for — invisible space at the
/// end of the list that pushes the last real item above the FAB's hit area.
const double kFabSafeBottomPadding = 88.0;
