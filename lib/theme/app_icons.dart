import 'package:flutter/material.dart';

/// Central icon registry — sibling of the theme colour palette.
///
/// Only icons that recur across multiple screens belong here. One-off icons
/// (e.g. the inbox empty-state's `inbox_outlined`) stay inline at their use
/// site — there's no benefit to abstracting something used once.
///
/// The names describe the *semantic role*, not the icon's appearance. That
/// way you can swap `complete` from a hollow circle to a square checkbox
/// without touching any call sites.
class AppIcons {
  AppIcons._();

  // ---------------------------------------------------------------------
  // Action icons — paired with onPressed handlers
  // ---------------------------------------------------------------------

  /// "Tap to mark this subtask complete." The hollow-circle shape is the
  /// universal checklist idiom (Todoist / Things / Reminders): tap → fill.
  /// Used on the current subtask in both Focus and Goal Detail screens.
  static const IconData complete = Icons.radio_button_unchecked;


  /// Points to the current subtask in a list.
  static const IconData currentSubtask = Icons.arrow_right_outlined;

  /// "Revert a completed subtask back to pending." The rewind glyph reads
  /// as "undo a state change" — less ambiguous than `Icons.undo`, which
  /// many users parse as a navigation back-button.
  static const IconData uncomplete = Icons.restore;

  /// Destructive action — remove a goal or subtask. Used everywhere a
  /// swipe-to-delete is exposed.
  static const IconData delete = Icons.delete_outline;

  /// Marks an item that is queued up
  static const IconData nextInQueue = Icons.subdirectory_arrow_right_outlined;

  /// "Add a new subtask to the goal."
  static const IconData addSubtask = Icons.playlist_add;

  /// "Break this subtask down into smaller, more actionable steps."
  static const IconData breakdown = Icons.call_split;

  /// "Generate or regenerate subtasks using AI."
  static const IconData aiGenerate = Icons.auto_awesome_outlined;

  // ---------------------------------------------------------------------
  // State icons — passive indicators, no onPressed
  // ---------------------------------------------------------------------

  /// "Queued — scheduled for later." A clock outline reads as "this has
  /// a time in its future" rather than "permission denied" (lock) or
  /// "pending your turn" (three-dot pending), making it clear the subtask
  /// is waiting for earlier steps to complete.
  static const IconData queued = Icons.pending_actions;
}
