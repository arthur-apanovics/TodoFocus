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

