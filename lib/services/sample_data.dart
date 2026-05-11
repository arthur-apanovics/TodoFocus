import '../models/enums.dart';
import '../models/goal.dart';
import '../models/sub_task.dart';

/// Static sample data for UI testing.
/// Only used by InMemoryGoalRepository — delete before shipping.
class SampleData {
  SampleData._(); // private constructor — this class is never instantiated

  static List<Goal> get goals => [
    _activeGoal,
    _inProgressGoal,
    _pausedGoal,
    _completedGoal,
    _inboxGoal,
    _noSubTasksGoal,
  ];

  // --- Active goal, mixed subtask states ---
  static final _activeGoal = Goal(
    goalId: 'sample-1',
    title: 'Learn Flutter',
    notes:
        'Build a solid foundation in Flutter and Dart by working through a real project.',
    dueDate: DateTime.now().add(const Duration(days: 30)),
    subtasks: [
      SubTask(
        subtaskId: 'sample-1-1',
        description: 'Understand the widget tree and how Flutter renders UI',
        state: SubTaskState.completed,
        assignedDate: DateTime.now().subtract(const Duration(days: 5)),
        completionDate: DateTime.now().subtract(const Duration(days: 4)),
      ),
      SubTask(
        subtaskId: 'sample-1-2',
        description: 'Build a stateful widget with setState',
        state: SubTaskState.completed,
        assignedDate: DateTime.now().subtract(const Duration(days: 3)),
        completionDate: DateTime.now().subtract(const Duration(days: 2)),
      ),
      SubTask(
        subtaskId: 'sample-1-3',
        description: 'Wire up Provider for state management across screens',
        state: SubTaskState.inProgress,
        assignedDate: DateTime.now().subtract(const Duration(days: 1)),
      ),
      SubTask(
        subtaskId: 'sample-1-4',
        description: 'Add persistence with a local database',
        state: SubTaskState.pending,
      ),
      SubTask(
        subtaskId: 'sample-1-5',
        description: 'Write widget tests for the main screens',
        state: SubTaskState.pending,
      ),
    ],
  );

  // --- Another active goal, mostly in progress ---
  static final _inProgressGoal = Goal(
    goalId: 'sample-2',
    title: 'Redesign personal website',
    notes:
        'Modernise the portfolio site with a cleaner layout and updated project showcases.',
    dueDate: DateTime.now().add(const Duration(days: 14)),
    subtasks: [
      SubTask(
        subtaskId: 'sample-2-1',
        description: 'Sketch new layout and gather design inspiration',
        state: SubTaskState.completed,
        assignedDate: DateTime.now().subtract(const Duration(days: 7)),
        completionDate: DateTime.now().subtract(const Duration(days: 6)),
      ),
      SubTask(
        subtaskId: 'sample-2-2',
        description: 'Set up new project with chosen framework',
        state: SubTaskState.completed,
        assignedDate: DateTime.now().subtract(const Duration(days: 5)),
        completionDate: DateTime.now().subtract(const Duration(days: 4)),
      ),
      SubTask(
        subtaskId: 'sample-2-3',
        description: 'Build homepage and about section',
        state: SubTaskState.inProgress,
        assignedDate: DateTime.now().subtract(const Duration(days: 2)),
      ),
      SubTask(
        subtaskId: 'sample-2-4',
        description: 'Add project showcase with screenshots',
        state: SubTaskState.pending,
      ),
    ],
  );

  // --- Paused goal ---
  static final _pausedGoal = Goal(
    goalId: 'sample-3',
    title: 'Read Atomic Habits',
    notes: 'Work through the book and capture actionable takeaways.',
    status: GoalStatus.paused,
    dueDate: DateTime.now().add(const Duration(days: 60)),
    subtasks: [
      SubTask(
        subtaskId: 'sample-3-1',
        description: 'Read chapters 1–4: The Fundamentals',
        state: SubTaskState.completed,
        assignedDate: DateTime.now().subtract(const Duration(days: 14)),
        completionDate: DateTime.now().subtract(const Duration(days: 12)),
      ),
      SubTask(
        subtaskId: 'sample-3-2',
        description: 'Read chapters 5–9: The 1st and 2nd Laws',
        state: SubTaskState.inProgress,
        assignedDate: DateTime.now().subtract(const Duration(days: 10)),
      ),
      SubTask(
        subtaskId: 'sample-3-3',
        description: 'Read chapters 10–15: The 3rd and 4th Laws',
        state: SubTaskState.pending,
      ),
      SubTask(
        subtaskId: 'sample-3-4',
        description: 'Write a one-page summary of key takeaways',
        state: SubTaskState.pending,
      ),
    ],
  );

  // --- Fully completed goal ---
  static final _completedGoal = Goal(
    goalId: 'sample-4',
    title: 'Set up development environment',
    notes: 'Get Flutter, VS Code, and all tooling configured and ready.',
    status: GoalStatus.completed,
    subtasks: [
      SubTask(
        subtaskId: 'sample-4-1',
        description: 'Install Flutter SDK and configure PATH',
        state: SubTaskState.completed,
        assignedDate: DateTime.now().subtract(const Duration(days: 20)),
        completionDate: DateTime.now().subtract(const Duration(days: 19)),
      ),
      SubTask(
        subtaskId: 'sample-4-2',
        description: 'Install VS Code extensions: Flutter, Dart, Error Lens',
        state: SubTaskState.completed,
        assignedDate: DateTime.now().subtract(const Duration(days: 19)),
        completionDate: DateTime.now().subtract(const Duration(days: 18)),
      ),
      SubTask(
        subtaskId: 'sample-4-3',
        description: 'Run flutter doctor and resolve any issues',
        state: SubTaskState.completed,
        assignedDate: DateTime.now().subtract(const Duration(days: 18)),
        completionDate: DateTime.now().subtract(const Duration(days: 17)),
      ),
    ],
  );

  // --- Inbox goal (captured, not yet decomposed) ---
  static final _inboxGoal = Goal(
    goalId: 'sample-5',
    title: 'Plan trip to Japan',
    notes: 'Research flights, accommodation, and itinerary for a 2-week trip.',
    status: GoalStatus.inbox,
    subtasks: [], // intentionally empty — not decomposed yet
  );

  // --- Active goal with no subtasks (edge case) ---
  static final _noSubTasksGoal = Goal(
    goalId: 'sample-6',
    title: 'Organise home office',
    notes: 'Declutter the desk, sort cables, and set up proper lighting.',
    dueDate: DateTime.now().add(const Duration(days: 7)),
    subtasks: [],
  );
}
