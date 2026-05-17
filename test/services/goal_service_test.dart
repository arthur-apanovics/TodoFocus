import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/models/enums.dart';
import 'package:todo_app/models/goal.dart';
import 'package:todo_app/models/sub_task.dart';
import 'package:todo_app/services/goal_repository.dart';
import 'package:todo_app/services/goal_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Goal makeGoal({
  String id = 'g1',
  GoalStatus status = GoalStatus.active,
  List<SubTask>? subtasks,
  bool isFocusedToday = false,
}) => Goal(
  goalId: id,
  title: 'Test goal',
  status: status,
  subtasks: subtasks,
  isFocusedToday: isFocusedToday,
);

SubTask makeSubTask(String id, {SubTaskState state = SubTaskState.pending}) =>
    SubTask(subtaskId: id, description: 'Step $id', state: state);

(GoalService, GoalRepository) makeService({List<Goal> seed = const []}) {
  final repo = InMemoryGoalRepository.empty();
  for (final g in seed) {
    repo.save(g);
  }
  return (GoalService(repo), repo);
}

void main() {
  // -------------------------------------------------------------------------
  // addSubTask
  // -------------------------------------------------------------------------

  group('addSubTask', () {
    test('persists the subtask to the repository', () {
      final (service, repo) = makeService(seed: [makeGoal()]);
      service.addSubTask('g1', 'Write the intro');
      final loaded = repo.findById('g1')!;
      expect(loaded.subtasks.length, 1);
      expect(loaded.subtasks.first.description, 'Write the intro');
    });

    test('assigns a non-empty subtaskId', () {
      final (service, repo) = makeService(seed: [makeGoal()]);
      service.addSubTask('g1', 'A step');
      expect(repo.findById('g1')!.subtasks.first.subtaskId, isNotEmpty);
    });

    test('is a no-op for an unknown goalId', () {
      final (service, repo) = makeService();
      service.addSubTask('nonexistent', 'A step');
      expect(repo.all, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // removeGoal
  // -------------------------------------------------------------------------

  group('removeGoal', () {
    test('removes the goal from the repository', () {
      final (service, repo) = makeService(seed: [makeGoal()]);
      service.removeGoal('g1');
      expect(repo.all, isEmpty);
    });

    test('does not affect other goals', () {
      final (service, repo) = makeService(seed: [
        makeGoal(id: 'g1'),
        makeGoal(id: 'g2'),
      ]);
      service.removeGoal('g1');
      expect(repo.all.map((g) => g.goalId), ['g2']);
    });
  });

  // -------------------------------------------------------------------------
  // updateGoal
  // -------------------------------------------------------------------------

  group('updateGoal', () {
    test('updates title when provided', () {
      final (service, repo) = makeService(seed: [makeGoal()]);
      service.updateGoal('g1', title: 'New title');
      expect(repo.findById('g1')!.title, 'New title');
    });

    test('updates notes when provided', () {
      final (service, repo) = makeService(seed: [makeGoal()]);
      service.updateGoal('g1', notes: 'Some notes');
      expect(repo.findById('g1')!.notes, 'Some notes');
    });

    test('does not overwrite title when only notes are passed', () {
      final goal = makeGoal();
      final (service, repo) = makeService(seed: [goal]);
      service.updateGoal('g1', notes: 'Only notes');
      expect(repo.findById('g1')!.title, 'Test goal');
    });

    test('updates difficulty when provided', () {
      final (service, repo) = makeService(seed: [makeGoal()]);
      service.updateGoal('g1', difficulty: GoalDifficulty.hard);
      expect(repo.findById('g1')!.difficulty, GoalDifficulty.hard);
    });

    test('does not overwrite difficulty when only title is passed', () {
      final goal = Goal(
        goalId: 'g1',
        title: 'T',
        difficulty: GoalDifficulty.impossible,
      );
      final (service, repo) = makeService(seed: [goal]);
      service.updateGoal('g1', title: 'Updated');
      expect(repo.findById('g1')!.difficulty, GoalDifficulty.impossible);
    });
  });

  // -------------------------------------------------------------------------
  // toggleFocusToday
  // -------------------------------------------------------------------------

  group('toggleFocusToday', () {
    test('sets isFocusedToday to true on first toggle', () {
      final goal = makeGoal();
      final (service, repo) = makeService(seed: [goal]);
      service.toggleFocusToday(goal);
      expect(repo.findById('g1')!.isFocusedToday, isTrue);
    });

    test('sets isFocusedToday back to false on second toggle', () {
      final goal = makeGoal(isFocusedToday: true);
      final (service, repo) = makeService(seed: [goal]);
      service.toggleFocusToday(goal);
      expect(repo.findById('g1')!.isFocusedToday, isFalse);
    });

    test('assigns todayOrder 0 when first goal is focused', () {
      final goal = makeGoal();
      final (service, repo) = makeService(seed: [goal]);
      service.toggleFocusToday(goal);
      expect(repo.findById('g1')!.todayOrder, 0);
    });

    test('appends to the end when another goal is already focused', () {
      final existing = makeGoal(id: 'g1', isFocusedToday: true);
      existing.todayOrder = 0;
      final newGoal = makeGoal(id: 'g2');
      final (service, repo) = makeService(seed: [existing, newGoal]);
      service.toggleFocusToday(newGoal);
      expect(repo.findById('g2')!.todayOrder, 1);
    });
  });

  // -------------------------------------------------------------------------
  // reorderTodayQueue
  // -------------------------------------------------------------------------

  group('reorderTodayQueue', () {
    List<Goal> focusedTrio() {
      final a = makeGoal(id: 'a', isFocusedToday: true)..todayOrder = 0;
      final b = makeGoal(id: 'b', isFocusedToday: true)..todayOrder = 1;
      final c = makeGoal(id: 'c', isFocusedToday: true)..todayOrder = 2;
      return [a, b, c];
    }

    test('moves a goal from the bottom to the top', () {
      final goals = focusedTrio();
      final (service, repo) = makeService(seed: goals);
      // ReorderableListView passes newIndex one past the target when moving down.
      service.reorderTodayQueue(goals, 2, 0); // move c to top
      expect(repo.findById('c')!.todayOrder, 0);
      expect(repo.findById('a')!.todayOrder, 1);
      expect(repo.findById('b')!.todayOrder, 2);
    });

    test('moves a goal from the top to the bottom', () {
      final goals = focusedTrio();
      final (service, repo) = makeService(seed: goals);
      // ReorderableListView convention: dropping past the end uses index N.
      service.reorderTodayQueue(goals, 0, 3); // move a to bottom
      expect(repo.findById('b')!.todayOrder, 0);
      expect(repo.findById('c')!.todayOrder, 1);
      expect(repo.findById('a')!.todayOrder, 2);
    });

    test('is a no-op when the move resolves to the same index', () {
      final goals = focusedTrio();
      final (service, repo) = makeService(seed: goals);
      service.reorderTodayQueue(goals, 1, 2); // newIndex normalised to 1 — no-op
      expect(repo.findById('a')!.todayOrder, 0);
      expect(repo.findById('b')!.todayOrder, 1);
      expect(repo.findById('c')!.todayOrder, 2);
    });
  });

  // -------------------------------------------------------------------------
  // completeCurrentSubTask
  // -------------------------------------------------------------------------

  group('completeCurrentSubTask', () {
    test('marks the first pending subtask done and persists', () {
      final goal = makeGoal(subtasks: [makeSubTask('s1'), makeSubTask('s2')]);
      final (service, repo) = makeService(seed: [goal]);
      service.completeCurrentSubTask('g1');
      final loaded = repo.findById('g1')!;
      expect(loaded.subtasks.first.state, SubTaskState.completed);
    });

    test('transitions goal to completed when the last subtask is done', () {
      final goal = makeGoal(subtasks: [makeSubTask('s1')]);
      final (service, repo) = makeService(seed: [goal]);
      service.completeCurrentSubTask('g1');
      expect(repo.findById('g1')!.status, GoalStatus.completed);
    });
  });

  // -------------------------------------------------------------------------
  // deleteSubTask
  // -------------------------------------------------------------------------

  group('deleteSubTask', () {
    test('removes the subtask from the goal', () {
      final goal = makeGoal(subtasks: [makeSubTask('s1'), makeSubTask('s2')]);
      final (service, repo) = makeService(seed: [goal]);
      service.deleteSubTask('g1', 's1');
      final loaded = repo.findById('g1')!;
      expect(loaded.subtasks.length, 1);
      expect(loaded.subtasks.first.subtaskId, 's2');
    });

    test('leaves the goal itself intact', () {
      final goal = makeGoal(subtasks: [makeSubTask('s1')]);
      final (service, repo) = makeService(seed: [goal]);
      service.deleteSubTask('g1', 's1');
      expect(repo.findById('g1'), isNotNull);
    });
  });

  // -------------------------------------------------------------------------
  // uncompleteSubTask
  // -------------------------------------------------------------------------

  group('uncompleteSubTask', () {
    test('reinserts the subtask before the current one', () {
      final goal = makeGoal(subtasks: [
        makeSubTask('s1', state: SubTaskState.completed),
        makeSubTask('s2'),
        makeSubTask('s3'),
      ]);
      final (service, repo) = makeService(seed: [goal]);
      service.uncompleteSubTask('g1', 's1');
      final ids = repo.findById('g1')!.subtasks.map((t) => t.subtaskId);
      expect(ids.toList(), ['s1', 's2', 's3']);
    });
  });

  // -------------------------------------------------------------------------
  // reorderSubTask
  // -------------------------------------------------------------------------

  group('reorderSubTask', () {
    test('persists the new order to the repository', () {
      final goal = makeGoal(subtasks: [
        makeSubTask('s1'),
        makeSubTask('s2'),
        makeSubTask('s3'),
      ]);
      final (service, repo) = makeService(seed: [goal]);
      service.reorderSubTask('g1', 2, 1); // move s3 before s2
      final ids = repo.findById('g1')!.subtasks.map((t) => t.subtaskId);
      expect(ids.toList(), ['s1', 's3', 's2']);
    });
  });

  // -------------------------------------------------------------------------
  // replacePendingSubTasks
  // -------------------------------------------------------------------------

  group('replacePendingSubTasks', () {
    test('removes pending subtasks and adds new ones, preserving completed', () {
      final goal = makeGoal(subtasks: [
        makeSubTask('s1', state: SubTaskState.completed),
        makeSubTask('s2'),
        makeSubTask('s3'),
      ]);
      final (service, repo) = makeService(seed: [goal]);
      service.replacePendingSubTasks('g1', ['New step A', 'New step B']);
      final loaded = repo.findById('g1')!;
      expect(loaded.subtasks.length, 3); // 1 completed + 2 new
      expect(loaded.subtasks[0].subtaskId, 's1');
      expect(loaded.subtasks[1].description, 'New step A');
      expect(loaded.subtasks[2].description, 'New step B');
    });

    test('replaces all subtasks when none are completed', () {
      final goal = makeGoal(subtasks: [makeSubTask('s1'), makeSubTask('s2')]);
      final (service, repo) = makeService(seed: [goal]);
      service.replacePendingSubTasks('g1', ['Only step']);
      final loaded = repo.findById('g1')!;
      expect(loaded.subtasks.length, 1);
      expect(loaded.subtasks.first.description, 'Only step');
    });

    test('is a no-op when descriptions list is empty', () {
      final goal = makeGoal(subtasks: [makeSubTask('s1')]);
      final (service, repo) = makeService(seed: [goal]);
      service.replacePendingSubTasks('g1', []);
      final loaded = repo.findById('g1')!;
      expect(loaded.subtasks.length, 1); // unchanged
    });

    test('is a no-op for an unknown goalId', () {
      final (service, repo) = makeService();
      service.replacePendingSubTasks('nonexistent', ['Step']);
      expect(repo.all, isEmpty);
    });
  });
}
