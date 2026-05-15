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

