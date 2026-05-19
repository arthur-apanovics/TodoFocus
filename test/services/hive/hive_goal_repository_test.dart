import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:todo_app/models/enums.dart';
import 'package:todo_app/models/goal.dart';
import 'package:todo_app/models/sub_task.dart';
import 'package:todo_app/services/hive/goal_dto.dart';
import 'package:todo_app/services/hive/hive_goal_repository.dart';
import 'package:todo_app/services/hive/sub_task_dto.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Goal makeGoal({
  String id = 'g1',
  GoalStatus status = GoalStatus.active,
  List<SubTask>? subtasks,
}) => Goal(
  goalId: id,
  title: 'Goal $id',
  status: status,
  subtasks: subtasks,
);

SubTask makeSubTask(String id, {SubTaskState state = SubTaskState.pending}) =>
    SubTask(subtaskId: id, description: 'Step $id', state: state);

// ---------------------------------------------------------------------------
// Test setup
// ---------------------------------------------------------------------------

late Directory _tmpDir;
late Box<GoalDto> _box;
late HiveGoalRepository _repo;

Future<void> openFreshRepo() async {
  _box = await Hive.openBox<GoalDto>('goals');
  _repo = HiveGoalRepository(_box, seed: false);
}

Future<void> closeFreshRepo() async {
  await _box.clear();
  await _box.close();
}

void main() {
  setUpAll(() async {
    _tmpDir = await Directory.systemTemp.createTemp('hive_test_');
    Hive.init(_tmpDir.path);
    Hive.registerAdapter(GoalDtoAdapter());
    Hive.registerAdapter(SubTaskDtoAdapter());
  });

  tearDownAll(() async {
    await Hive.close();
    await _tmpDir.delete(recursive: true);
  });

  setUp(openFreshRepo);
  tearDown(closeFreshRepo);

  // -------------------------------------------------------------------------
  // Basic save / findById / all
  // -------------------------------------------------------------------------

  group('save and findById', () {
    test('saved goal can be retrieved by id', () {
      _repo.save(makeGoal());
      final loaded = _repo.findById('g1');
      expect(loaded, isNotNull);
      expect(loaded!.goalId, 'g1');
      expect(loaded.title, 'Goal g1');
    });

    test('all returns every saved goal', () {
      _repo.save(makeGoal(id: 'g1'));
      _repo.save(makeGoal(id: 'g2'));
      expect(_repo.all.map((g) => g.goalId), containsAll(['g1', 'g2']));
    });

    test('findById returns null for an unknown id', () {
      expect(_repo.findById('missing'), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // delete
  // -------------------------------------------------------------------------

  group('delete', () {
    test('removes the goal from the box', () {
      _repo.save(makeGoal());
      _repo.delete('g1');
      expect(_repo.findById('g1'), isNull);
      expect(_repo.all, isEmpty);
    });

    test('does not affect other goals', () {
      _repo.save(makeGoal(id: 'g1'));
      _repo.save(makeGoal(id: 'g2'));
      _repo.delete('g1');
      expect(_repo.all.map((g) => g.goalId), ['g2']);
    });
  });

  // -------------------------------------------------------------------------
  // isFocusedToday persistence
  // Bug: this flag was missing from _toDto and was silently reset on reload.
  // -------------------------------------------------------------------------

  // -------------------------------------------------------------------------
  // GoalStatus persistence and migration
  // -------------------------------------------------------------------------

  group('status round-trip', () {
    test('active status survives a save/reload cycle', () {
      _repo.save(makeGoal(status: GoalStatus.active));
      expect(_repo.findById('g1')!.status, GoalStatus.active);
    });

    test('inbox status survives a save/reload cycle', () {
      _repo.save(makeGoal(status: GoalStatus.inbox));
      expect(_repo.findById('g1')!.status, GoalStatus.inbox);
    });

    test('completed status survives a save/reload cycle', () {
      _repo.save(makeGoal(status: GoalStatus.completed));
      expect(_repo.findById('g1')!.status, GoalStatus.completed);
    });

    test('legacy paused status is migrated to active on load', () {
      // Write a DTO directly with the legacy "paused" string value to
      // simulate data written by an older version of the app.
      final dto = GoalDto()
        ..goalId = 'legacy'
        ..title = 'Legacy goal'
        ..notes = ''
        ..status = 'paused'
        ..dueDate = null
        ..subtasks = [];
      _box.put('legacy', dto);

      expect(_repo.findById('legacy')!.status, GoalStatus.active);
    });
  });

  // -------------------------------------------------------------------------
  // Subtask persistence
  // -------------------------------------------------------------------------

  group('subtask round-trip', () {
    test('subtasks are preserved in order', () {
      final goal = makeGoal(subtasks: [
        makeSubTask('s1'),
        makeSubTask('s2'),
        makeSubTask('s3'),
      ]);
      _repo.save(goal);
      final ids = _repo.findById('g1')!.subtasks.map((t) => t.subtaskId);
      expect(ids.toList(), ['s1', 's2', 's3']);
    });

    test('subtask state is persisted', () {
      final goal = makeGoal(subtasks: [
        makeSubTask('s1', state: SubTaskState.completed),
        makeSubTask('s2'),
      ]);
      _repo.save(goal);
      final loaded = _repo.findById('g1')!;
      expect(loaded.subtasks[0].state, SubTaskState.completed);
      expect(loaded.subtasks[1].state, SubTaskState.pending);
    });

    test('goal with no subtasks round-trips cleanly', () {
      _repo.save(makeGoal(subtasks: []));
      expect(_repo.findById('g1')!.subtasks, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Full field round-trip — KEEP THIS TEST UP TO DATE
  //
  // This is the enforcement mechanism for the DTO ↔ Domain mapping layer.
  // Whenever a new field is added to GoalDto / Goal, add it here with a
  // non-default value so the test will fail if _toDomain or _toDto is not
  // updated. The previous emoji bug (field existed in the DTO but was never
  // read/written by the mappers) was caught by exactly this pattern.
  // -------------------------------------------------------------------------

  group('full field round-trip', () {
    test('every Goal field survives a save/reload cycle', () {
      final due = DateTime(2030, 6, 15);
      final original = Goal(
        goalId: 'full',
        title: 'Full field test',
        notes: 'Some notes',
        status: GoalStatus.inbox,
        difficulty: GoalDifficulty.hard,
        dueDate: due,
        emoji: '🚀',
        subtasks: [
          SubTask(
            subtaskId: 'st1',
            description: 'Step one',
            state: SubTaskState.completed,
          ),
          SubTask(
            subtaskId: 'st2',
            description: 'Step two',
            state: SubTaskState.pending,
          ),
        ],
      );

      _repo.save(original);
      final loaded = _repo.findById('full')!;

      expect(loaded.goalId, original.goalId, reason: 'goalId');
      expect(loaded.title, original.title, reason: 'title');
      expect(loaded.notes, original.notes, reason: 'notes');
      expect(loaded.status, original.status, reason: 'status');
      expect(loaded.difficulty, original.difficulty, reason: 'difficulty');
      expect(loaded.dueDate, original.dueDate, reason: 'dueDate');
      expect(loaded.emoji, original.emoji, reason: 'emoji');

      expect(loaded.subtasks.length, 2, reason: 'subtask count');
      expect(loaded.subtasks[0].subtaskId, 'st1', reason: 'subtask[0].id');
      expect(loaded.subtasks[0].state, SubTaskState.completed,
          reason: 'subtask[0].state');
      expect(loaded.subtasks[1].subtaskId, 'st2', reason: 'subtask[1].id');
      expect(loaded.subtasks[1].state, SubTaskState.pending,
          reason: 'subtask[1].state');
    });
  });

  // -------------------------------------------------------------------------
  // save is idempotent (no duplication on repeated saves)
  // Bug: using addAll() instead of putAll() caused duplicate entries.
  // -------------------------------------------------------------------------

  group('idempotent save', () {
    test('saving the same goal twice does not create a duplicate', () {
      final goal = makeGoal();
      _repo.save(goal);
      _repo.save(goal);
      expect(_repo.all.length, 1);
    });

    test('second save overwrites the first', () {
      _repo.save(makeGoal());
      final updated = makeGoal()..title = 'Updated';
      _repo.save(updated);
      expect(_repo.findById('g1')!.title, 'Updated');
      expect(_repo.all.length, 1);
    });
  });
}
