import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/models/enums.dart';
import 'package:todo_app/models/goal.dart';
import 'package:todo_app/models/sub_task.dart';
import 'package:todo_app/services/focus_list_service.dart';
import 'package:todo_app/services/goal_repository.dart';
import 'package:todo_app/services/goal_service.dart';

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

(GoalService, GoalRepository) makeService({List<Goal> seed = const []}) {
  final repo = InMemoryGoalRepository.empty();
  for (final g in seed) {
    repo.save(g);
  }
  final focus = FocusListService.inMemory();
  return (GoalService(repo, focus), repo);
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

  // -------------------------------------------------------------------------
  // queueGoal
  // -------------------------------------------------------------------------

  group('queueGoal', () {
    test('transitions an inbox goal with subtasks to active', () {
      final goal = makeGoal(
        status: GoalStatus.inbox,
        subtasks: [makeSubTask('s1')],
      );
      final (service, repo) = makeService(seed: [goal]);
      service.queueGoal('g1');
      expect(repo.findById('g1')!.status, GoalStatus.active);
    });

    test('transitions an inbox goal with no subtasks to active', () {
      // Caller is responsible for disabling the button when empty; the
      // service still queues bare goals if asked to.
      final goal = makeGoal(status: GoalStatus.inbox);
      final (service, repo) = makeService(seed: [goal]);
      service.queueGoal('g1');
      expect(repo.findById('g1')!.status, GoalStatus.active);
    });

    test('lands on completed when every subtask is already done', () {
      final goal = makeGoal(
        status: GoalStatus.inbox,
        subtasks: [makeSubTask('s1', state: SubTaskState.completed)],
      );
      final (service, repo) = makeService(seed: [goal]);
      service.queueGoal('g1');
      expect(repo.findById('g1')!.status, GoalStatus.completed);
    });

    test('is a no-op for a non-inbox goal', () {
      final goal = makeGoal(subtasks: [makeSubTask('s1')]); // active
      final (service, repo) = makeService(seed: [goal]);
      service.queueGoal('g1');
      expect(repo.findById('g1')!.status, GoalStatus.active);
    });

    test('is a no-op for an unknown goalId', () {
      final (service, repo) = makeService();
      service.queueGoal('nonexistent');
      expect(repo.all, isEmpty);
    });
  });
}
