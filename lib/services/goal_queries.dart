import '../models/enums.dart';
import '../models/goal.dart';
import '../models/sub_task.dart';
import 'goal_repository.dart';

class GoalQueries {
  final GoalRepository _repository;

  GoalQueries(this._repository);

  List<Goal> get all => _repository.all;

  List<Goal> get goals =>
      _repository.all.where((g) => g.status != GoalStatus.inbox).toList();

  List<Goal> get inbox =>
      _repository.all.where((g) => g.status == GoalStatus.inbox).toList();

  List<Goal> get todayQueue {
    final queue = _repository.all
        .where(
          (g) => g.isFocusedToday && g.isDailyAssignable && g.subtasks.isNotEmpty,
        )
        .toList();
    queue.sort((a, b) => a.todayOrder.compareTo(b.todayOrder));
    return queue;
  }

  List<SubTask> pendingSubTasksFor(String goalId) =>
      _repository
          .findById(goalId)
          ?.subtasks
          .where((t) => t.state == SubTaskState.pending)
          .toList() ??
      [];
}
