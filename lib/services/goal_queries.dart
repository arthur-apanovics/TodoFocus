import '../models/enums.dart';
import '../models/goal.dart';
import '../models/sub_task.dart';
import 'goal_repository.dart';

class GoalQueries {
  final GoalRepository _repository;

  GoalQueries(this._repository);

  List<Goal> get all => _repository.all;

  /// The daily quick-task list goal, or null if it doesn't exist yet.
  /// There is at most one such goal (the first found with isDailyTaskList).
  /// Visibility is controlled by [DisplayPreferences.dailyTaskListEnabled];
  /// this getter always returns it regardless of the preference so callers
  /// that manage the goal directly (e.g. Settings) can access it.
  Goal? get dailyTaskGoal =>
      _repository.all.where((g) => g.isDailyTaskList).firstOrNull;

  List<Goal> get goals => _repository.all
      .where((g) => g.status == GoalStatus.active && !g.isDailyTaskList)
      .toList();

  List<Goal> get completedGoals => _repository.all
      .where((g) => g.status == GoalStatus.completed && !g.isDailyTaskList)
      .toList();

  List<Goal> get archivedGoals => _repository.all
      .where((g) => g.status == GoalStatus.archived && !g.isDailyTaskList)
      .toList();

  List<Goal> get inbox => _repository.all
      .where((g) => g.status == GoalStatus.inbox && !g.isDailyTaskList)
      .toList();

  List<SubTask> pendingSubTasksFor(String goalId) =>
      _repository
          .findById(goalId)
          ?.subtasks
          .where((t) => t.state == SubTaskState.pending)
          .toList() ??
      [];
}
