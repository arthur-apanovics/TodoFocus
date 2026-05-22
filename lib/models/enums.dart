enum GoalStatus {
  inbox,
  active,
  completed,
  archived,
}

/// Lifecycle states a subtask moves through.
///
/// • [pending]   — actively waiting to be worked on (default state).
/// • [snoozed]   — temporarily paused. Pairs with [SubTask.snoozedUntil] —
///                 the [SchedulingService] auto-transitions back to
///                 [pending] when that time arrives. Snoozing the current
///                 step puts the whole goal on hold (no current task,
///                 goal sinks in the sort).
/// • [completed] — finished, frozen.
enum SubTaskState {
  pending,
  snoozed,
  completed,
}

/// Cadence at which a recurring goal repeats.
///
/// • [daily]       — every day at the configured reset time.
/// • [weeklyDays]  — on a chosen set of weekdays (1=Mon … 7=Sun).
/// • [everyNDays]  — every N days from the last completion / reset.
/// • [monthly]     — on a specific day of the month; gracefully clamps to
///                   the last day of the month when the chosen day doesn't
///                   exist (e.g. day 31 in February).
enum RecurrenceFrequency {
  daily,
  weeklyDays,
  everyNDays,
  monthly,
}

enum GoalSortOrder { dateAdded, urgency, smart }

/// Controls how many subtask steps are shown inline on each card in the goals
/// list. [compact] shows none (default). The rest show the current pending
/// step plus up to N additional pending steps beneath it.
enum GoalListLayout {
  compact,       // No inline subtasks
  current,       // Current step only
  currentPlus2,  // Current + up to 2 next pending steps
  currentPlus4,  // Current + up to 4 next pending steps
  ;

  String get displayName => switch (this) {
    GoalListLayout.compact => 'Compact',
    GoalListLayout.current => 'Current step',
    GoalListLayout.currentPlus2 => 'Current + 2 next',
    GoalListLayout.currentPlus4 => 'Current + 4 next',
  };
}

/// Controls how much detail a focus surface (the in-app Focus tab and the
/// home-screen widget) renders per focused goal. Mirrors [GoalListLayout] but
/// kept distinct so the two surfaces can be tuned independently — a tiny
/// home-screen widget and the full Focus tab have very different space.
///
/// The non-compact variants render a window of `1 + extraSteps` rows centred
/// on the current step. The Focus tab fills the window forward with pending
/// steps and then backfills with completed steps so the row count is stable
/// across completions. The widget only shows pending steps (no completed
/// history) since corner real-estate is scarce.
enum FocusLayout {
  compact,       // Goal header only — no subtask rows (header carries a CTA)
  current,       // Current step only (deprecated for Focus tab, still used by widget default)
  currentPlus2,  // Window of 3 rows around the current step
  currentPlus4,  // Window of 5 rows around the current step
  ;

  String get displayName => switch (this) {
    FocusLayout.compact => 'Compact',
    FocusLayout.current => 'Single step',
    FocusLayout.currentPlus2 => 'Three steps',
    FocusLayout.currentPlus4 => 'Five steps',
  };

  /// Extra rows the window allocates beyond the current step. `compact`
  /// shows nothing (the header is the whole card) and `current` shows just
  /// the current step. Bigger values widen the window symmetrically — the
  /// Focus tab biases forward (pending) then backfills with completed.
  int get extraSteps => switch (this) {
    FocusLayout.compact => 0,
    FocusLayout.current => 0,
    FocusLayout.currentPlus2 => 2,
    FocusLayout.currentPlus4 => 4,
  };
}

/// How granularly the LLM breaks down a goal into subtasks.
/// The min/max counts for each level are configurable in LLM settings.
enum GoalDifficulty {
  easy,
  hard,
  impossible;

  String get displayName => switch (this) {
    GoalDifficulty.easy => 'Easy',
    GoalDifficulty.hard => 'Hard',
    GoalDifficulty.impossible => 'Impossible',
  };
}

