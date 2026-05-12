import 'package:collection/collection.dart';
import '../models/enums.dart';
import '../models/sub_task.dart';

class Goal {
  final String goalId;
  String title;
  String notes;
  GoalStatus status;
  final DateTime? dueDate;
  bool isFocusedToday;
  final List<SubTask> subtasks;

  Goal({
    required this.goalId,
    required this.title,
    this.notes = '',
    this.status = GoalStatus.active,
    this.dueDate,
    this.isFocusedToday = false,
    List<SubTask>? subtasks,
  }) : subtasks = subtasks ?? [];

  // --- Computed properties ---

  bool get isCompleted => status == GoalStatus.completed;

  bool get isDailyAssignable =>
      status != GoalStatus.completed && status != GoalStatus.inbox;

  // The subtask the user should work on right now
  // Always the first non-completed subtask — inProgress is implicit
  SubTask? get currentSubTask =>
      subtasks.firstWhereOrNull((t) => t.state == SubTaskState.pending);

  // The next subtask after the current one — for the "peek" in Focus screen
  SubTask? get nextSubTask {
    final current = currentSubTask;
    if (current == null) return null;

    final currentIndex = subtasks.indexOf(current);
    final remaining = subtasks.skip(currentIndex + 1);
    return remaining.firstWhereOrNull((t) => t.state == SubTaskState.pending);
  }

  // Used by the UI to decide how to render each subtask tile
  bool isCurrentSubTask(SubTask subtask) => subtask == currentSubTask;

  int get completedSubtaskCount =>
      subtasks.where((t) => t.state == SubTaskState.completed).length;

  double get progressPercent =>
      subtasks.isEmpty ? 0 : completedSubtaskCount / subtasks.length;

  // --- Mutations ---

  void addSubTask(SubTask task) => subtasks.add(task);

  void removeSubTask(String subtaskId) {
    subtasks.removeWhere((t) => t.subtaskId == subtaskId);
    _recalculateStatus();
  }

  // Complete the current subtask — next pending one becomes current implicitly
  void completeCurrentSubTask() {
    final current = currentSubTask;
    if (current == null) return;

    current.markComplete();
    _recalculateStatus();
  }

  // Undo a completed subtask — reinserts just before the current subtask
  // so it becomes the new current
  void uncompleteSubTask(String subtaskId) {
    final subtask = subtasks.firstWhereOrNull((t) => t.subtaskId == subtaskId);
    if (subtask == null || subtask.state != SubTaskState.completed) return;

    subtask.markIncomplete();
    subtasks.remove(subtask);

    // Find the current subtask after removal — nullable, handled explicitly
    final current = currentSubTask;
    final insertAt = current == null
        ? subtasks
              .length // no pending subtasks — append to end
        : subtasks.indexOf(current); // insert just before current

    subtasks.insert(insertAt, subtask);
    _recalculateStatus();
  }

  void reorderSubTask(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final movingTask = subtasks[oldIndex];
    if (movingTask.state == SubTaskState.completed) return;

    final firstPendingIndex = subtasks.indexWhere(
      (t) => t.state == SubTaskState.pending,
    );
    if (newIndex < firstPendingIndex) {
      newIndex = firstPendingIndex;
    }

    subtasks.removeAt(oldIndex);
    subtasks.insert(newIndex, movingTask);
  }

  void pause() => status = GoalStatus.paused;

  void resume() {
    status = GoalStatus.active;
    _recalculateStatus();
  }

  void _recalculateStatus() {
    if (status == GoalStatus.paused) return;
    final allDone =
        subtasks.isNotEmpty &&
        subtasks.every((t) => t.state == SubTaskState.completed);
    status = allDone ? GoalStatus.completed : GoalStatus.active;
  }

  // --- Serialisation ---

  Map<String, dynamic> toJson() => {
    'goalId': goalId,
    'title': title,
    'notes': notes,
    'status': status.name,
    'dueDate': dueDate?.toIso8601String(),
    'isFocusedToday': isFocusedToday,
    'subtasks': subtasks.map((t) => t.toJson()).toList(),
  };

  factory Goal.fromJson(Map<String, dynamic> json) {
    return Goal(
      goalId: json['goalId'] as String,
      title: json['title'] as String,
      notes: json['notes'] as String? ?? '',
      status: GoalStatus.values.byName(json['status'] as String),
      dueDate: json['dueDate'] != null
          ? DateTime.parse(json['dueDate'] as String)
          : null,
      isFocusedToday: json['isFocusedToday'] as bool? ?? false,
      subtasks:
          (json['subtasks'] as List<dynamic>?)
              ?.map((t) => SubTask.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
