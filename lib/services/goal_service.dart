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

  void toggleFocusToday(Goal goal) {
    goal.isFocusedToday = !goal.isFocusedToday;
    if (goal.isFocusedToday) {
      // Append to the bottom of the today queue by giving this goal a higher
      // todayOrder than any currently-focused goal.
      final maxOrder = _repository.all
          .where((g) => g.isFocusedToday && g.goalId != goal.goalId)
          .fold<int>(-1, (m, g) => g.todayOrder > m ? g.todayOrder : m);
      goal.todayOrder = maxOrder + 1;
    }
    _repository.save(goal);
  }

  // Reorders the today queue based on the visible list shown to the user.
  // Caller passes the *current* ordered queue (e.g. queries.todayQueue) and
  // the indices supplied by ReorderableListView. We normalise newIndex,
  // rebuild the list, then write back 0..n-1 to each goal's todayOrder.
  void reorderTodayQueue(
    List<Goal> currentQueue,
    int oldIndex,
    int newIndex,
  ) {
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;

    final reordered = List<Goal>.from(currentQueue);
    final moving = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moving);

    for (var i = 0; i < reordered.length; i++) {
      final goal = reordered[i];
      if (goal.todayOrder != i) {
        goal.todayOrder = i;
        _repository.save(goal);
      }
    }
  }

  // --- SubTask operations ---

  void addSubTask(String goalId, String description) {
    final goal = _repository.findById(goalId);
    if (goal == null) return;

    goal.addSubTask(SubTask(subtaskId: _uuid.v4(), description: description));
    _repository.save(goal);
  }

  // Replaces a single subtask with one or more smaller steps. Used both by
  // the manual split flow (user types replacements) and the LLM-driven
  // breakdown flow (provider returns 1–3 replacement descriptions).
  void splitSubTask(
    String goalId,
    String subtaskId,
    List<String> descriptions,
  ) {
    if (descriptions.isEmpty) return;
    final goal = _repository.findById(goalId);
    if (goal == null) return;
    goal.replaceSubTask(
      subtaskId,
      descriptions
          .map((d) => SubTask(subtaskId: _uuid.v4(), description: d))
          .toList(),
    );
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
