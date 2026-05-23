import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/models/enums.dart';
import 'package:todo_app/models/goal.dart';
import 'package:todo_app/models/sub_task.dart';
import 'package:todo_app/services/focus_list_service.dart';
import 'package:todo_app/services/goal_repository.dart';
import 'package:todo_app/services/goal_service.dart';
import 'package:todo_app/services/llm/decomposed_step.dart';

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
      service.replacePendingSubTasks('g1', const [
        DecomposedStep('New step A'),
        DecomposedStep('New step B'),
      ]);
      final loaded = repo.findById('g1')!;
      expect(loaded.subtasks.length, 3); // 1 completed + 2 new
      expect(loaded.subtasks[0].subtaskId, 's1');
      expect(loaded.subtasks[1].description, 'New step A');
      expect(loaded.subtasks[2].description, 'New step B');
    });

    test('replaces all subtasks when none are completed', () {
      final goal = makeGoal(subtasks: [makeSubTask('s1'), makeSubTask('s2')]);
      final (service, repo) = makeService(seed: [goal]);
      service.replacePendingSubTasks('g1', const [DecomposedStep('Only step')]);
      final loaded = repo.findById('g1')!;
      expect(loaded.subtasks.length, 1);
      expect(loaded.subtasks.first.description, 'Only step');
    });

    test('is a no-op when steps list is empty', () {
      final goal = makeGoal(subtasks: [makeSubTask('s1')]);
      final (service, repo) = makeService(seed: [goal]);
      service.replacePendingSubTasks('g1', const []);
      final loaded = repo.findById('g1')!;
      expect(loaded.subtasks.length, 1); // unchanged
    });

    test('is a no-op for an unknown goalId', () {
      final (service, repo) = makeService();
      service.replacePendingSubTasks(
          'nonexistent', const [DecomposedStep('Step')]);
      expect(repo.all, isEmpty);
    });

    test('threads LLM-supplied time estimates into new subtasks', () {
      final goal = makeGoal(subtasks: [makeSubTask('s1')]);
      final (service, repo) = makeService(seed: [goal]);
      service.replacePendingSubTasks('g1', const [
        DecomposedStep('Step with estimate', estimatedMinutes: 25),
      ]);
      expect(repo.findById('g1')!.subtasks.first.estimatedMinutes, 25);
    });
  });

  // -------------------------------------------------------------------------
  // Time estimates
  // -------------------------------------------------------------------------

  group('setSubTaskEstimate', () {
    test('sets the estimate on a pending subtask', () {
      final goal = makeGoal(subtasks: [makeSubTask('s1')]);
      final (service, repo) = makeService(seed: [goal]);
      service.setSubTaskEstimate('g1', 's1', 30);
      expect(repo.findById('g1')!.subtasks.first.estimatedMinutes, 30);
    });

    test('clears the estimate when passed null', () {
      final st = makeSubTask('s1');
      st.estimatedMinutes = 45;
      final (service, repo) = makeService(seed: [makeGoal(subtasks: [st])]);
      service.setSubTaskEstimate('g1', 's1', null);
      expect(repo.findById('g1')!.subtasks.first.estimatedMinutes, isNull);
    });

    test('is a no-op for an unknown subtaskId', () {
      final goal = makeGoal(subtasks: [makeSubTask('s1')]);
      final (service, repo) = makeService(seed: [goal]);
      service.setSubTaskEstimate('g1', 'unknown', 30);
      expect(repo.findById('g1')!.subtasks.first.estimatedMinutes, isNull);
    });

    test('is a no-op for an unknown goalId', () {
      final (service, repo) = makeService();
      service.setSubTaskEstimate('nope', 's1', 30);
      expect(repo.all, isEmpty);
    });
  });

  group('bulkSetSubTaskEstimates', () {
    test('applies estimates to matching subtasks', () {
      final goal = makeGoal(subtasks: [
        makeSubTask('a'),
        makeSubTask('b'),
        makeSubTask('c'),
      ]);
      final (service, repo) = makeService(seed: [goal]);
      service.bulkSetSubTaskEstimates('g1', const {'a': 10, 'b': 20});
      final loaded = repo.findById('g1')!.subtasks;
      expect(loaded[0].estimatedMinutes, 10);
      expect(loaded[1].estimatedMinutes, 20);
      expect(loaded[2].estimatedMinutes, isNull); // not in map
    });

    test('silently skips IDs that do not match any subtask', () {
      final goal = makeGoal(subtasks: [makeSubTask('a')]);
      final (service, repo) = makeService(seed: [goal]);
      service.bulkSetSubTaskEstimates('g1', const {'a': 5, 'bogus': 99});
      expect(repo.findById('g1')!.subtasks.first.estimatedMinutes, 5);
    });

    test('is a no-op when map is empty', () {
      final st = makeSubTask('a');
      st.estimatedMinutes = 42;
      final (service, repo) = makeService(seed: [makeGoal(subtasks: [st])]);
      service.bulkSetSubTaskEstimates('g1', const {});
      expect(repo.findById('g1')!.subtasks.first.estimatedMinutes, 42);
    });
  });

  group('setShowTimeEstimatesOverride', () {
    test('sets the per-goal override', () {
      final (service, repo) = makeService(seed: [makeGoal()]);
      service.setShowTimeEstimatesOverride('g1', true);
      expect(repo.findById('g1')!.showTimeEstimatesOverride, isTrue);
    });

    test('clears the override when passed null', () {
      final g = makeGoal()..showTimeEstimatesOverride = false;
      final (service, repo) = makeService(seed: [g]);
      service.setShowTimeEstimatesOverride('g1', null);
      expect(repo.findById('g1')!.showTimeEstimatesOverride, isNull);
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

  // -------------------------------------------------------------------------
  // completeSubTask — sequential enforcement
  // -------------------------------------------------------------------------

  group('completeSubTask', () {
    test('completes the first pending subtask', () {
      final goal = makeGoal(
        subtasks: [makeSubTask('s1'), makeSubTask('s2')],
      );
      final (service, repo) = makeService(seed: [goal]);
      service.completeSubTask('g1', 's1');
      final loaded = repo.findById('g1')!;
      expect(loaded.subtasks[0].state, SubTaskState.completed);
      expect(loaded.subtasks[1].state, SubTaskState.pending);
    });

    test('throws StateError when attempting to skip a subtask', () {
      final goal = makeGoal(
        subtasks: [makeSubTask('s1'), makeSubTask('s2')],
      );
      final (service, _) = makeService(seed: [goal]);
      // s2 is not the first pending — domain model must reject this.
      expect(
        () => service.completeSubTask('g1', 's2'),
        throwsA(isA<StateError>()),
      );
    });

    test('throws when trying to complete an already-completed subtask', () {
      final goal = makeGoal(
        subtasks: [
          makeSubTask('s1', state: SubTaskState.completed),
          makeSubTask('s2'),
        ],
      );
      final (service, _) = makeService(seed: [goal]);
      // s1 is completed — no pending subtask has that id; s2 is current.
      expect(
        () => service.completeSubTask('g1', 's1'),
        throwsA(isA<StateError>()),
      );
    });

    test('is a no-op for an unknown goalId', () {
      final (service, repo) = makeService();
      // Should not throw — unknown goal is silently ignored at service level.
      expect(() => service.completeSubTask('nonexistent', 's1'), returnsNormally);
      expect(repo.all, isEmpty);
    });

    test('transitions goal to completed when last subtask is done', () {
      final goal = makeGoal(
        subtasks: [makeSubTask('s1')],
      );
      final (service, repo) = makeService(seed: [goal]);
      service.completeSubTask('g1', 's1');
      expect(repo.findById('g1')!.status, GoalStatus.completed);
    });
  });

  // -------------------------------------------------------------------------
  // Goal.completeSubTask — domain model level
  // -------------------------------------------------------------------------

  // -------------------------------------------------------------------------
  // setSubTaskAutoSleep
  // -------------------------------------------------------------------------

  group('setSubTaskAutoSleep', () {
    test('stores the duration on a queued pending subtask', () {
      final goal = makeGoal(
        subtasks: [makeSubTask('s1'), makeSubTask('s2')],
      );
      final (service, repo) = makeService(seed: [goal]);

      service.setSubTaskAutoSleep('g1', 's2', const Duration(days: 3));

      final loaded = repo.findById('g1')!;
      // Still pending; duration stashed for when s1 completes.
      expect(loaded.subtasks[1].state, SubTaskState.pending);
      expect(loaded.subtasks[1].autoSleepDuration, const Duration(days: 3));
    });

    test('immediately snoozes when applied to the current subtask', () {
      final goal = makeGoal(
        subtasks: [makeSubTask('s1')],
      );
      final (service, repo) = makeService(seed: [goal]);

      service.setSubTaskAutoSleep('g1', 's1', const Duration(hours: 1));

      final loaded = repo.findById('g1')!;
      expect(loaded.subtasks[0].state, SubTaskState.snoozed);
      expect(loaded.subtasks[0].snoozedUntil, isNotNull);
    });

    test('clearing removes the stored duration', () {
      final goal = makeGoal(
        subtasks: [makeSubTask('s1'), makeSubTask('s2')],
      );
      goal.subtasks[1].autoSleepDuration = const Duration(days: 3);
      final (service, repo) = makeService(seed: [goal]);

      service.setSubTaskAutoSleep('g1', 's2', null);

      expect(repo.findById('g1')!.subtasks[1].autoSleepDuration, isNull);
    });

    test('ignores completed subtasks', () {
      final goal = makeGoal(subtasks: [
        makeSubTask('s1', state: SubTaskState.completed),
      ]);
      final (service, repo) = makeService(seed: [goal]);

      service.setSubTaskAutoSleep('g1', 's1', const Duration(days: 1));

      expect(repo.findById('g1')!.subtasks[0].autoSleepDuration, isNull);
    });
  });

  group('Goal.completeSubTask', () {
    test('completes the current subtask', () {
      final goal = makeGoal(subtasks: [makeSubTask('s1'), makeSubTask('s2')]);
      goal.completeSubTask('s1');
      expect(goal.subtasks[0].state, SubTaskState.completed);
      expect(goal.currentSubTask?.subtaskId, 's2');
    });

    test('throws StateError for a non-current pending subtask', () {
      final goal = makeGoal(subtasks: [makeSubTask('s1'), makeSubTask('s2')]);
      expect(() => goal.completeSubTask('s2'), throwsA(isA<StateError>()));
    });

    test('throws StateError when no subtasks are pending', () {
      final goal = makeGoal(subtasks: [
        makeSubTask('s1', state: SubTaskState.completed),
      ]);
      expect(() => goal.completeSubTask('s1'), throwsA(isA<StateError>()));
    });
  });
}
