import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/models/enums.dart';
import 'package:todo_app/models/goal.dart';
import 'package:todo_app/models/sub_task.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Goal makeGoal({
  String id = 'g1',
  GoalStatus status = GoalStatus.active,
  List<SubTask>? subtasks,
}) => Goal(
  goalId: id,
  title: 'Test goal',
  status: status,
  subtasks: subtasks,
);

SubTask makeSubTask(String id, {SubTaskState state = SubTaskState.pending}) =>
    SubTask(subtaskId: id, description: 'Step $id', state: state);

void main() {
  // -------------------------------------------------------------------------
  // addSubTask
  // -------------------------------------------------------------------------

  group('addSubTask', () {
    test('appends the subtask', () {
      final g = makeGoal(status: GoalStatus.inbox);
      g.addSubTask(makeSubTask('a'));
      expect(g.subtasks.length, 1);
      expect(g.subtasks.first.subtaskId, 'a');
    });

    test('leaves an inbox goal in inbox (planning stays put)', () {
      // The two-stage workflow keeps planning goals in the inbox until
      // the user explicitly queues them via GoalService.queueGoal().
      final g = makeGoal(status: GoalStatus.inbox);
      g.addSubTask(makeSubTask('a'));
      expect(g.status, GoalStatus.inbox);
    });

    test('restores a completed goal to active', () {
      final g = makeGoal();
      g.addSubTask(makeSubTask('a'));
      g.completeCurrentSubTask(); // → completed
      expect(g.status, GoalStatus.completed);
      g.addSubTask(makeSubTask('b')); // new pending subtask → active again
      expect(g.status, GoalStatus.active);
    });
  });

  // -------------------------------------------------------------------------
  // completeCurrentSubTask
  // -------------------------------------------------------------------------

  group('completeCurrentSubTask', () {
    test('marks first pending subtask as completed', () {
      final g = makeGoal(subtasks: [makeSubTask('a'), makeSubTask('b')]);
      g.completeCurrentSubTask();
      expect(g.subtasks.first.state, SubTaskState.completed);
    });

    test('advances the current pointer to the next pending subtask', () {
      final g = makeGoal(subtasks: [makeSubTask('a'), makeSubTask('b')]);
      g.completeCurrentSubTask();
      expect(g.currentSubTask?.subtaskId, 'b');
    });

    test('transitions goal to completed when all subtasks are done', () {
      final g = makeGoal(subtasks: [makeSubTask('a')]);
      g.completeCurrentSubTask();
      expect(g.status, GoalStatus.completed);
      expect(g.currentSubTask, isNull);
    });

    test('is a no-op when there are no pending subtasks', () {
      // Construct with a completed subtask — status stays active because
      // the constructor does not call _recalculateStatus.
      final done = makeSubTask('a', state: SubTaskState.completed);
      final g = makeGoal(subtasks: [done]);
      g.completeCurrentSubTask();
      expect(g.subtasks.first.state, SubTaskState.completed); // unchanged
    });
  });

  // -------------------------------------------------------------------------
  // uncompleteSubTask
  // -------------------------------------------------------------------------

  group('uncompleteSubTask', () {
    test('reinserts the subtask just before the current one', () {
      // [a✓, b, c] → uncomplete a → [a, b, c] (a becomes new current)
      final g = makeGoal(subtasks: [
        makeSubTask('a', state: SubTaskState.completed),
        makeSubTask('b'),
        makeSubTask('c'),
      ]);
      g.uncompleteSubTask('a');
      expect(g.subtasks.map((t) => t.subtaskId).toList(), ['a', 'b', 'c']);
      expect(g.currentSubTask?.subtaskId, 'a');
    });

    test('appends to the end when all other subtasks are already completed', () {
      // [a✓, b✓] → uncomplete a → [b✓, a]  (a is the only pending, at end)
      final g = makeGoal(subtasks: [
        makeSubTask('a', state: SubTaskState.completed),
        makeSubTask('b', state: SubTaskState.completed),
      ]);
      g.uncompleteSubTask('a');
      expect(g.subtasks.last.subtaskId, 'a');
      expect(g.currentSubTask?.subtaskId, 'a');
    });

    test('marks the subtask as pending', () {
      final g = makeGoal(subtasks: [
        makeSubTask('a', state: SubTaskState.completed),
        makeSubTask('b'),
      ]);
      g.uncompleteSubTask('a');
      expect(g.subtasks.first.state, SubTaskState.pending);
    });

    test('transitions goal back to active from completed', () {
      final g = makeGoal(subtasks: [makeSubTask('a')]);
      g.completeCurrentSubTask(); // → completed
      g.uncompleteSubTask('a');
      expect(g.status, GoalStatus.active);
    });

    test('is a no-op when the subtask is already pending', () {
      final g = makeGoal(subtasks: [makeSubTask('a'), makeSubTask('b')]);
      g.uncompleteSubTask('a'); // 'a' is already pending
      expect(g.subtasks.map((t) => t.subtaskId).toList(), ['a', 'b']);
    });
  });

  // -------------------------------------------------------------------------
  // reorderSubTask
  // -------------------------------------------------------------------------

  group('reorderSubTask', () {
    test('moves a pending subtask to a new position', () {
      final g = makeGoal(subtasks: [
        makeSubTask('a'),
        makeSubTask('b'),
        makeSubTask('c'),
      ]);
      g.reorderSubTask(2, 1); // move 'c' before 'b'
      expect(g.subtasks.map((t) => t.subtaskId).toList(), ['a', 'c', 'b']);
    });

    test('is a no-op for a completed subtask', () {
      final g = makeGoal(subtasks: [
        makeSubTask('a', state: SubTaskState.completed),
        makeSubTask('b'),
        makeSubTask('c'),
      ]);
      g.reorderSubTask(0, 2); // attempt to move completed 'a'
      expect(g.subtasks.first.subtaskId, 'a'); // unchanged
    });

    test('clamps target index to the first pending position', () {
      // [a✓, b, c] — try to drag 'c' before the completed block
      final g = makeGoal(subtasks: [
        makeSubTask('a', state: SubTaskState.completed),
        makeSubTask('b'),
        makeSubTask('c'),
      ]);
      g.reorderSubTask(2, 0); // would put 'c' before 'a' — should be clamped
      expect(g.subtasks[0].subtaskId, 'a'); // completed stays first
      expect(g.subtasks[1].subtaskId, 'c'); // clamped to index 1
      expect(g.subtasks[2].subtaskId, 'b');
    });
  });

  // -------------------------------------------------------------------------
  // Computed properties
  // -------------------------------------------------------------------------

  group('progressPercent', () {
    test('is 0.0 when there are no subtasks', () {
      expect(makeGoal().progressPercent, 0.0);
    });

    test('is 0.5 when half the subtasks are done', () {
      final g = makeGoal(subtasks: [
        makeSubTask('a', state: SubTaskState.completed),
        makeSubTask('b'),
      ]);
      expect(g.progressPercent, 0.5);
    });

    test('is 1.0 when all subtasks are done', () {
      final g = makeGoal(subtasks: [
        makeSubTask('a', state: SubTaskState.completed),
      ]);
      expect(g.progressPercent, 1.0);
    });
  });

  group('completedSubtaskCount', () {
    test('counts only completed subtasks', () {
      final g = makeGoal(subtasks: [
        makeSubTask('a', state: SubTaskState.completed),
        makeSubTask('b', state: SubTaskState.completed),
        makeSubTask('c'),
      ]);
      expect(g.completedSubtaskCount, 2);
    });
  });

  group('isDailyAssignable', () {
    test('is false for inbox goals', () {
      expect(makeGoal(status: GoalStatus.inbox).isDailyAssignable, isFalse);
    });

    test('is false for completed goals', () {
      expect(makeGoal(status: GoalStatus.completed).isDailyAssignable, isFalse);
    });

    test('is true for active goals', () {
      expect(makeGoal(status: GoalStatus.active).isDailyAssignable, isTrue);
    });
  });

  group('currentSubTask and nextSubTask', () {
    test('currentSubTask is the first pending subtask', () {
      final g = makeGoal(subtasks: [
        makeSubTask('a', state: SubTaskState.completed),
        makeSubTask('b'),
        makeSubTask('c'),
      ]);
      expect(g.currentSubTask?.subtaskId, 'b');
    });

    test('nextSubTask is the second pending subtask', () {
      final g = makeGoal(subtasks: [
        makeSubTask('a'),
        makeSubTask('b'),
        makeSubTask('c'),
      ]);
      expect(g.nextSubTask?.subtaskId, 'b');
    });

    test('nextSubTask is null when only one pending subtask remains', () {
      final g = makeGoal(subtasks: [
        makeSubTask('a', state: SubTaskState.completed),
        makeSubTask('b'),
      ]);
      expect(g.nextSubTask, isNull);
    });

    test('both are null when there are no pending subtasks', () {
      expect(makeGoal().currentSubTask, isNull);
      expect(makeGoal().nextSubTask, isNull);
    });
  });

  // -------------------------------------------------------------------------
  // replacePendingSubTasks
  // -------------------------------------------------------------------------

  group('replacePendingSubTasks', () {
    test('keeps completed subtasks and appends new pending ones', () {
      final g = makeGoal(subtasks: [
        makeSubTask('a', state: SubTaskState.completed),
        makeSubTask('b'),
        makeSubTask('c'),
      ]);
      g.replacePendingSubTasks([
        SubTask(subtaskId: 'x', description: 'New step'),
      ]);
      // 'a' preserved, 'b' and 'c' removed, 'x' appended
      expect(g.subtasks.length, 2);
      expect(g.subtasks[0].subtaskId, 'a');
      expect(g.subtasks[1].subtaskId, 'x');
    });

    test('replaces all subtasks when none are completed', () {
      final g = makeGoal(subtasks: [makeSubTask('a'), makeSubTask('b')]);
      g.replacePendingSubTasks([SubTask(subtaskId: 'x', description: 'New')]);
      expect(g.subtasks.length, 1);
      expect(g.subtasks.first.subtaskId, 'x');
    });

    test('goal remains active when new subtasks are added', () {
      final g = makeGoal(subtasks: [
        makeSubTask('a', state: SubTaskState.completed),
      ]);
      g.replacePendingSubTasks([SubTask(subtaskId: 'x', description: 'New')]);
      expect(g.status, GoalStatus.active);
    });

    test('preserves all completed subtasks when there are no pending ones', () {
      final g = makeGoal(subtasks: [
        makeSubTask('a', state: SubTaskState.completed),
        makeSubTask('b', state: SubTaskState.completed),
      ]);
      g.replacePendingSubTasks([SubTask(subtaskId: 'x', description: 'New')]);
      expect(g.subtasks.length, 3);
      expect(g.subtasks[0].subtaskId, 'a');
      expect(g.subtasks[1].subtaskId, 'b');
      expect(g.subtasks[2].subtaskId, 'x');
    });
  });

  // -------------------------------------------------------------------------
  // difficulty serialisation
  // -------------------------------------------------------------------------

  group('difficulty serialisation', () {
    test('round-trips through toJson / fromJson for all values', () {
      for (final d in GoalDifficulty.values) {
        final goal = Goal(goalId: 'g1', title: 'T', difficulty: d);
        final restored = Goal.fromJson(goal.toJson());
        expect(restored.difficulty, d, reason: 'failed for ${d.name}');
      }
    });

    test('defaults to easy when the JSON key is absent', () {
      final json = <String, dynamic>{
        'goalId': 'g1',
        'title': 'T',
        'notes': '',
        'status': 'active',
        'subtasks': <dynamic>[],
      };
      expect(Goal.fromJson(json).difficulty, GoalDifficulty.easy);
    });
  });

  // -------------------------------------------------------------------------
  // archived goal guard
  // -------------------------------------------------------------------------

  group('archived goal', () {
    test('stays archived when completeCurrentSubTask is called', () {
      final g = Goal(
        goalId: 'g1',
        title: 'T',
        status: GoalStatus.archived,
        subtasks: [makeSubTask('a')],
      );
      g.completeCurrentSubTask();
      expect(g.status, GoalStatus.archived);
    });
  });
}
