import '../models/enums.dart';
import '../models/goal.dart';
import '../models/sub_task.dart';
import 'goal_repository.dart';

class GoalQueries {
  final GoalRepository _repository;

  GoalQueries(this._repository);

  List<Goal> get all => _repository.all;

  List<Goal> get active =>
      _repository.all.where((g) => g.status == GoalStatus.active).toList();

  List<Goal> get todayQueue =>
      _repository.all.where((g) => g.isDailyAssignable).toList();

  List<SubTask> pendingSubTasksFor(String goalId) =>
      _repository
          .findById(goalId)
          ?.subtasks
          .where((t) => t.state == SubTaskState.pending)
          .toList() ??
      [];
}
