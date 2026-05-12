import 'package:uuid/uuid.dart'; // we'll add this below
import '../models/enums.dart';
import '../models/goal.dart';
import '../models/sub_task.dart';

class GoalDecompositionService {
  final Uuid _uuid = const Uuid();

  // The single public method — takes raw user input, returns a structured Goal.
  // This is the method signature that stays the same when the LLM replaces the internals.
  Goal decompose({
    required String title,
    String? description,
    DateTime? dueDate,
  }) {
    final goalId = _uuid.v4();

    return Goal(
      goalId: goalId,
      title: title,
      notes: description ?? '',
      dueDate: dueDate,
      subtasks: _scaffoldSubTasks(goalId),
    );
  }

  // Captures a raw goal into the inbox without decomposing it
  Goal captureToInbox({required String title, String? description}) {
    return Goal(
      goalId: _uuid.v4(),
      title: title,
      notes: description ?? '',
      status: GoalStatus.inbox,
      subtasks: [], // no subtasks yet — decomposition happens later
    );
  }

  // Private — the LLM will replace this method body entirely, nothing else changes
  List<SubTask> _scaffoldSubTasks(String goalId) {
    final templates = [
      'Define what done looks like for this goal',
      'Break down the first concrete action',
      'Complete the first action',
      'Review progress and adjust if needed',
    ];

    // All start as pending — the first one is implicitly
    // current because it's the first non-completed subtask
    return templates
        .map(
          (description) =>
              SubTask(subtaskId: _uuid.v4(), description: description),
        )
        .toList();
  }
}
