import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/models/enums.dart';
import 'package:todo_app/models/goal.dart';
import 'package:todo_app/models/recurrence.dart';
import 'package:todo_app/models/sub_task.dart';
import 'package:todo_app/services/goal_repository.dart';
import 'package:todo_app/services/scheduling_service.dart';

// ── Helpers ──────────────────────────────────────────────────────────────

Goal makeGoal({
  String id = 'g1',
  Recurrence? recurrence,
  DateTime? nextOccurrenceAt,
  List<SubTask>? subtasks,
}) =>
    Goal(
      goalId: id,
      title: 'Test goal',
      recurrence: recurrence,
      nextOccurrenceAt: nextOccurrenceAt,
      subtasks: subtasks,
    );

SubTask makeSubTask(
  String id, {
  SubTaskState state = SubTaskState.pending,
  DateTime? snoozedUntil,
}) =>
    SubTask(
      subtaskId: id,
      description: 'Step $id',
      state: state,
      snoozedUntil: snoozedUntil,
    );

(SchedulingService, GoalRepository) makeService({List<Goal> seed = const []}) {
  final repo = InMemoryGoalRepository.empty();
  for (final g in seed) {
    repo.save(g);
  }
  return (SchedulingService(repo), repo);
}

void main() {
  // ──────────────────────────────────────────────────────────────────────
  // Snooze wake-up
  // ──────────────────────────────────────────────────────────────────────

  group('checkAndProcess — snooze wake-ups', () {
    test('wakes a subtask whose snooze has elapsed', () {
      final past = DateTime.now().subtract(const Duration(minutes: 1));
      final st = makeSubTask('s1',
          state: SubTaskState.snoozed, snoozedUntil: past);
      final (svc, repo) = makeService(seed: [makeGoal(subtasks: [st])]);

      final tick = svc.checkAndProcess();

      expect(tick.wokenSubtasks.length, 1);
      expect(tick.wokenSubtasks.first.subtask.subtaskId, 's1');
      final loaded = repo.findById('g1')!;
      expect(loaded.subtasks.first.state, SubTaskState.pending);
      expect(loaded.subtasks.first.snoozedUntil, isNull);
      expect(loaded.lastResumedAt, isNotNull);
    });

    test('does not wake a snooze still in the future', () {
      final future = DateTime.now().add(const Duration(hours: 1));
      final st = makeSubTask('s1',
          state: SubTaskState.snoozed, snoozedUntil: future);
      final (svc, repo) = makeService(seed: [makeGoal(subtasks: [st])]);

      final tick = svc.checkAndProcess();

      expect(tick.wokenSubtasks, isEmpty);
      expect(repo.findById('g1')!.subtasks.first.state,
          SubTaskState.snoozed);
    });

    test('idempotent — second call returns an empty tick', () {
      final past = DateTime.now().subtract(const Duration(minutes: 1));
      final st = makeSubTask('s1',
          state: SubTaskState.snoozed, snoozedUntil: past);
      final (svc, _) = makeService(seed: [makeGoal(subtasks: [st])]);

      svc.checkAndProcess();
      final tick2 = svc.checkAndProcess();

      expect(tick2.isEmpty, isTrue);
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  // Recurrence reset
  // ──────────────────────────────────────────────────────────────────────

  group('checkAndProcess — recurrence reset', () {
    test('resets subtasks when the next occurrence has arrived', () {
      final past = DateTime.now().subtract(const Duration(minutes: 1));
      final goal = makeGoal(
        recurrence: Recurrence.daily(),
        nextOccurrenceAt: past,
        subtasks: [
          makeSubTask('s1', state: SubTaskState.completed),
          makeSubTask('s2', state: SubTaskState.completed),
        ],
      );
      final (svc, repo) = makeService(seed: [goal]);

      final tick = svc.checkAndProcess();

      expect(tick.resetGoals.length, 1);
      final loaded = repo.findById('g1')!;
      expect(loaded.subtasks.every((s) => s.state == SubTaskState.pending),
          isTrue);
      expect(loaded.lastIterationSummary, contains('Step s1'));
      expect(loaded.lastIterationSummary, contains('Step s2'));
      expect(loaded.lastResumedAt, isNotNull);
      // Next occurrence got recomputed.
      expect(
          loaded.nextOccurrenceAt!.isAfter(DateTime.now()), isTrue);
    });

    test('does not reset before the next occurrence', () {
      final future = DateTime.now().add(const Duration(hours: 2));
      final goal = makeGoal(
        recurrence: Recurrence.daily(),
        nextOccurrenceAt: future,
        subtasks: [makeSubTask('s1', state: SubTaskState.completed)],
      );
      final (svc, repo) = makeService(seed: [goal]);

      final tick = svc.checkAndProcess();

      expect(tick.resetGoals, isEmpty);
      expect(repo.findById('g1')!.subtasks.first.state,
          SubTaskState.completed);
    });

    test('records a non-empty iteration summary for empty completions', () {
      final past = DateTime.now().subtract(const Duration(minutes: 1));
      final goal = makeGoal(
        recurrence: Recurrence.daily(),
        nextOccurrenceAt: past,
        subtasks: [makeSubTask('s1')], // pending, never completed
      );
      final (svc, repo) = makeService(seed: [goal]);

      svc.checkAndProcess();

      expect(repo.findById('g1')!.lastIterationSummary,
          'No steps completed last cycle.');
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  // Recurrence + snooze in the same tick
  // ──────────────────────────────────────────────────────────────────────

  group('checkAndProcess — combined', () {
    test('handles wake-up + recurrence reset on the same goal', () {
      final past = DateTime.now().subtract(const Duration(minutes: 1));
      final goal = makeGoal(
        recurrence: Recurrence.daily(),
        nextOccurrenceAt: past,
        subtasks: [
          makeSubTask('s1',
              state: SubTaskState.snoozed, snoozedUntil: past),
        ],
      );
      final (svc, repo) = makeService(seed: [goal]);

      final tick = svc.checkAndProcess();

      expect(tick.wokenSubtasks.length, 1);
      expect(tick.resetGoals.length, 1);
      final loaded = repo.findById('g1')!;
      // After reset, subtask is pending and snooze metadata is cleared.
      expect(loaded.subtasks.first.state, SubTaskState.pending);
      expect(loaded.subtasks.first.snoozedUntil, isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  // configureRecurrence
  // ──────────────────────────────────────────────────────────────────────

  group('configureRecurrence', () {
    test('precomputes nextOccurrenceAt from the reference time', () {
      final (svc, repo) = makeService(seed: [makeGoal()]);
      final ref = DateTime(2026, 5, 1, 10);

      svc.configureRecurrence(
        repo.findById('g1')!,
        recurrence: Recurrence.daily(),
        referenceTime: ref,
      );

      final loaded = repo.findById('g1')!;
      expect(loaded.recurrence, isNotNull);
      expect(loaded.nextOccurrenceAt, DateTime(2026, 5, 2));
    });

    test('clears nextOccurrenceAt when recurrence is null', () {
      final (svc, repo) = makeService(seed: [
        makeGoal(
          recurrence: Recurrence.daily(),
          nextOccurrenceAt: DateTime(2026, 5, 2),
        ),
      ]);

      svc.configureRecurrence(repo.findById('g1')!, recurrence: null);

      final loaded = repo.findById('g1')!;
      expect(loaded.recurrence, isNull);
      expect(loaded.nextOccurrenceAt, isNull);
    });
  });
}
