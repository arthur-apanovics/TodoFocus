import '../models/enums.dart';
import '../models/goal.dart';
import 'goal_repository.dart';

class GoalService {
  final GoalRepository _repository;

  // Dependency injection — like C# constructor injection
  // Makes this testable without a real repository
  GoalService(this._repository);

  void addGoal(Goal goal) => _repository.save(goal);

  void removeGoal(String goalId) => _repository.delete(goalId);

  void pauseGoal(String goalId) {
    final goal = _repository.findById(goalId);
    if (goal == null) return;
    goal.pause();
    _repository.save(goal);
  }

  void resumeGoal(String goalId) {
    final goal = _repository.findById(goalId);
    if (goal == null) return;
    goal.resume();
    _repository.save(goal);
  }

  void transitionSubTask(
    String goalId,
    String subtaskId,
    SubTaskState newState,
  ) {
    final goal = _repository.findById(goalId);
    if (goal == null) {
      return;
    }

    goal.transitionSubTask(subtaskId, newState); // Goal manages itself
    _repository.save(goal);
  }
}
