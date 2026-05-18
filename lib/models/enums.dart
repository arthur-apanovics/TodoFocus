enum GoalStatus {
  inbox,
  active,
  completed,
  archived,
}

enum SubTaskState {
  pending,
  completed
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

