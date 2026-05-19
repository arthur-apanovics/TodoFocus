import '../models/enums.dart';
import '../models/goal.dart';
import '../models/sub_task.dart';
import 'goal_repository.dart';

class GoalQueries {
  final GoalRepository _repository;

  GoalQueries(this._repository);

  List<Goal> get all => _repository.all;

  List<Goal> get goals =>
      _repository.all.where((g) => g.status == GoalStatus.active).toList();

  List<Goal> get completedGoals =>
      _repository.all.where((g) => g.status == GoalStatus.completed).toList();

  List<Goal> get archivedGoals =>
      _repository.all.where((g) => g.status == GoalStatus.archived).toList();

  List<Goal> get inbox =>
      _repository.all.where((g) => g.status == GoalStatus.inbox).toList();

  List<SubTask> pendingSubTasksFor(String goalId) =>
      _repository
          .findById(goalId)
          ?.subtasks
          .where((t) => t.state == SubTaskState.pending)
          .toList() ??
      [];
}
