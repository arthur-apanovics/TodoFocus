import 'package:uuid/uuid.dart';
import '../models/goal.dart';
import '../models/sub_task.dart';
import 'goal_repository.dart';

class GoalService {
  final GoalRepository _repository;
  final _uuid = const Uuid();

  GoalService(this._repository);

  // --- Goal operations ---

  void addGoal(Goal goal) => _repository.save(goal);

  void removeGoal(String goalId) => _repository.delete(goalId);

  void updateGoal(String goalId, {String? title, String? notes}) {
    final goal = _repository.findById(goalId);
    if (goal == null) return;

    if (title != null) goal.title = title;
    if (notes != null) goal.notes = notes;
    _repository.save(goal);
  }

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

  void toggleFocusToday(String goalId) {
    final goal = _repository.findById(goalId);
    if (goal == null) return;

    goal.isFocusedToday = !goal.isFocusedToday;
    _repository.save(goal);
  }

  // --- SubTask operations ---

  void addSubTask(String goalId, String description) {
    final goal = _repository.findById(goalId);
    if (goal == null) return;

    goal.addSubTask(SubTask(subtaskId: _uuid.v4(), description: description));
    _repository.save(goal);
  }

  void deleteSubTask(String goalId, String subtaskId) {
    final goal = _repository.findById(goalId);
    if (goal == null) return;

    goal.removeSubTask(subtaskId);
    _repository.save(goal);
  }

  void updateSubTaskDescription(
    String goalId,
    String subtaskId,
    String newDescription,
  ) {
    final goal = _repository.findById(goalId);
    if (goal == null) return;
    final subtask = goal.subtasks.firstWhere((t) => t.subtaskId == subtaskId);
    subtask.updateDescription(newDescription);
    _repository.save(goal);
  }

  void reorderSubTask(String goalId, int oldIndex, int newIndex) {
    final goal = _repository.findById(goalId);
    if (goal == null) return;
    goal.reorderSubTask(oldIndex, newIndex);
    _repository.save(goal);
  }

  void completeCurrentSubTask(String goalId) {
    final goal = _repository.findById(goalId);
    if (goal == null) return;
    goal.completeCurrentSubTask();
    _repository.save(goal);
  }

  void uncompleteSubTask(String goalId, String subtaskId) {
    final goal = _repository.findById(goalId);
    if (goal == null) return;
    goal.uncompleteSubTask(subtaskId);
    _repository.save(goal);
  }
}
