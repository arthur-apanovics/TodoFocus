import 'package:todo_app/models/enums.dart';
import 'package:todo_app/models/sub_task.dart';

class Goal {
  final String goalId;
  final String title;
  String notes; // mutable — user can edit
  GoalStatus status; // mutable
  final DateTime? dueDate; // nullable — not every goal has a deadline
  final List<SubTask> subtasks;

  Goal({
    required this.goalId,
    required this.title,
    this.notes = '',
    this.status = GoalStatus.paused,
    this.dueDate,
    List<SubTask>? subtasks, // nullable in constructor, defaulted below
  }) : subtasks = subtasks ?? [];

  bool get isCompleted => status == GoalStatus.completed;

  bool get isDailyAssignable =>
      status != GoalStatus.completed && status != GoalStatus.inbox;

  int get completedSubtaskCount =>
      subtasks.where((t) => t.state == SubTaskState.completed).length;

  double get progressPercent =>
      subtasks.isEmpty ? 0 : completedSubtaskCount / subtasks.length;

  void pause() {
    status = GoalStatus.paused;
  }

  void resume() {
    // Recalculate rather than blindly setting active
    // — subtasks might all be done already
    status = GoalStatus.active;
    _recalculateStatus();
  }

  void addSubTask(SubTask task) {
    subtasks.add(task);
  }

  void transitionSubTask(String subtaskId, SubTaskState newState) {
    final subtask = subtasks.firstWhere(
      (t) => t.subtaskId == subtaskId,
      orElse: () => throw ArgumentError('SubTask not found: $subtaskId'),
    );

    switch (newState) {
      case SubTaskState.pending:
        subtask.markPending();
      case SubTaskState.inProgress:
        subtask.markInProgress();
      case SubTaskState.completed:
        subtask.markComplete();
    }

    _recalculateStatus(); // private — callers never need to know this happens
  }

  void _recalculateStatus() {
    if (status == GoalStatus.paused) return;
    final allDone =
        subtasks.isNotEmpty &&
        subtasks.every((t) => t.state == SubTaskState.completed);
    status = allDone ? GoalStatus.completed : GoalStatus.active;
  }

  Map<String, dynamic> toJson() => {
    'goalId': goalId,
    'title': title,
    'notes': notes,
    'status': status.name,
    'dueDate': dueDate?.toIso8601String(),
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
      subtasks:
          (json['subtasks'] as List<dynamic>?)
              ?.map((t) => SubTask.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
