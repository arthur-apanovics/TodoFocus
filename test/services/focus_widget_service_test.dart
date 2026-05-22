import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/models/enums.dart';
import 'package:todo_app/models/goal.dart';
import 'package:todo_app/models/sub_task.dart';
import 'package:todo_app/services/focus_list_service.dart';
import 'package:todo_app/services/focus_widget_service.dart';
import 'package:todo_app/services/goal_repository.dart';

// ── Helpers ──────────────────────────────────────────────────────────────

SubTask makeSubTask(String id, {SubTaskState state = SubTaskState.pending}) =>
    SubTask(subtaskId: id, description: 'Step $id', state: state);

Goal makeGoal({
  String id = 'g1',
  String title = 'Test goal',
  String? emoji,
  List<SubTask>? subtasks,
}) =>
    Goal(goalId: id, title: title, emoji: emoji, subtasks: subtasks);

/// Decodes [FocusWidgetService.buildPayload] into a (layout, rows) pair.
({String layout, List<dynamic> rows}) decode(String json) {
  final map = jsonDecode(json) as Map<String, dynamic>;
  return (layout: map['layout'] as String, rows: map['rows'] as List<dynamic>);
}

void main() {
  group('FocusWidgetService.buildPayload', () {
    test('empty focus list yields a payload with no rows', () {
      final repo = InMemoryGoalRepository.empty();
      final focus = FocusListService.inMemory();

      final payload = decode(
        FocusWidgetService.buildPayload(FocusLayout.current, focus, repo),
      );

      expect(payload.layout, 'current');
      expect(payload.rows, isEmpty);
    });

    test('current layout yields a single row, flagged as current', () async {
      final repo = InMemoryGoalRepository.empty();
      repo.save(makeGoal(emoji: 'rocket', subtasks: [
        makeSubTask('s1'),
        makeSubTask('s2'),
      ]));
      final focus = FocusListService.inMemory();
      await focus.focusGoalFully('g1', repo);

      final payload = decode(
        FocusWidgetService.buildPayload(FocusLayout.current, focus, repo),
      );

      expect(payload.rows.length, 1);
      final row = payload.rows.first as Map<String, dynamic>;
      expect(row['step'], 'Step s1');
      expect(row['goalId'], 'g1');
      expect(row['subtaskId'], 's1');
      expect(row['goalEmoji'], 'rocket');
      expect(row['isCurrent'], isTrue);
    });

    test('compact layout also yields a single row', () async {
      final repo = InMemoryGoalRepository.empty();
      repo.save(makeGoal(subtasks: [makeSubTask('s1'), makeSubTask('s2')]));
      final focus = FocusListService.inMemory();
      await focus.focusGoalFully('g1', repo);

      final payload = decode(
        FocusWidgetService.buildPayload(FocusLayout.compact, focus, repo),
      );

      expect(payload.layout, 'compact');
      expect(payload.rows.length, 1);
    });

    test('currentPlus2 caps the queue at three pending rows', () async {
      final repo = InMemoryGoalRepository.empty();
      repo.save(makeGoal(subtasks: [
        for (var i = 1; i <= 5; i++) makeSubTask('s$i'),
      ]));
      final focus = FocusListService.inMemory();
      await focus.focusGoalFully('g1', repo);

      final payload = decode(
        FocusWidgetService.buildPayload(FocusLayout.currentPlus2, focus, repo),
      );

      expect(payload.rows.length, 3);
      expect((payload.rows.first as Map)['isCurrent'], isTrue);
      expect((payload.rows[1] as Map)['isCurrent'], isFalse);
    });

    test('currentPlus4 caps the queue at five pending rows', () async {
      final repo = InMemoryGoalRepository.empty();
      repo.save(makeGoal(subtasks: [
        for (var i = 1; i <= 8; i++) makeSubTask('s$i'),
      ]));
      final focus = FocusListService.inMemory();
      await focus.focusGoalFully('g1', repo);

      final payload = decode(
        FocusWidgetService.buildPayload(FocusLayout.currentPlus4, focus, repo),
      );

      expect(payload.rows.length, 5);
    });

    test('completed subtasks are skipped — first pending becomes current',
        () async {
      final repo = InMemoryGoalRepository.empty();
      repo.save(makeGoal(subtasks: [
        makeSubTask('s1', state: SubTaskState.completed),
        makeSubTask('s2'),
      ]));
      final focus = FocusListService.inMemory();
      await focus.focusGoalFully('g1', repo);

      final payload = decode(
        FocusWidgetService.buildPayload(FocusLayout.currentPlus2, focus, repo),
      );

      expect(payload.rows.length, 1);
      final row = payload.rows.first as Map<String, dynamic>;
      expect(row['subtaskId'], 's2');
      expect(row['isCurrent'], isTrue);
    });

    test(
        'partial focus: selected step completed → backfills from goal\'s remaining pending',
        () async {
      // Simulate: user focuses only s1 (partial, not fully-focused), then
      // completes s1 (via widget tap or in-app). The focus group retains the
      // stale s1 entry. Pass 1 of pickPendingForGoal finds nothing pending in
      // the focus list, so Pass 2 backfills from the goal's remaining pending
      // subtasks up to maxRowsPerGoal — preventing the visible-row count from
      // collapsing every time the user completes a focused step.
      final repo = InMemoryGoalRepository.empty();
      final goal = makeGoal(subtasks: [
        makeSubTask('s1'), // pending initially so focusSubtask accepts it
        makeSubTask('s2'),
        makeSubTask('s3'),
      ]);
      repo.save(goal);
      final focus = FocusListService.inMemory();
      await focus.focusSubtask('g1', 's1', repo);

      // Simulate s1 being completed — update the repo directly.
      goal.completeCurrentSubTask(); // s1 → completed, s2 becomes current
      repo.save(goal);

      final payload = decode(
        FocusWidgetService.buildPayload(FocusLayout.currentPlus2, focus, repo),
      );

      // currentPlus2 → maxRowsPerGoal = 3. Pass 1: nothing (s1 is completed,
      // s2/s3 not focused). Pass 2 backfills with s2, s3 in goal order.
      expect(payload.rows.length, 2);
      final first = payload.rows[0] as Map<String, dynamic>;
      final second = payload.rows[1] as Map<String, dynamic>;
      expect(first['subtaskId'], 's2');
      expect(first['isCurrent'], isTrue);
      expect(second['subtaskId'], 's3');
      expect(second['isCurrent'], isFalse);
    });

    test('partial focus: all subtasks done → no rows for that goal', () async {
      final repo = InMemoryGoalRepository.empty();
      final goal = makeGoal(subtasks: [makeSubTask('s1')]);
      repo.save(goal);
      final focus = FocusListService.inMemory();
      await focus.focusSubtask('g1', 's1', repo);

      // Complete the only subtask.
      goal.completeCurrentSubTask();
      repo.save(goal);

      final payload = decode(
        FocusWidgetService.buildPayload(FocusLayout.currentPlus2, focus, repo),
      );

      // Goal completed; fallback currentSubTask is null → no rows.
      expect(payload.rows, isEmpty);
    });

    test(
        'mixed: partial goal stale + fully-focused goal — both render correctly',
        () async {
      final repo = InMemoryGoalRepository.empty();
      final goalA = makeGoal(
        id: 'g1',
        title: 'Goal A',
        subtasks: [makeSubTask('s1'), makeSubTask('s2')],
      );
      repo.save(goalA);
      repo.save(makeGoal(
        id: 'g2',
        title: 'Goal B',
        subtasks: [makeSubTask('s3')],
      ));
      final focus = FocusListService.inMemory();
      await focus.focusSubtask('g1', 's1', repo); // partial focus on g1
      await focus.focusGoalFully('g2', repo); // fully focused g2

      // Complete s1 so g1's focus group has no more pending focused steps.
      goalA.completeCurrentSubTask();
      repo.save(goalA);

      final payload = decode(
        FocusWidgetService.buildPayload(FocusLayout.currentPlus2, focus, repo),
      );

      // Row 0: g1's fallback (s2), isCurrent=true
      // Row 1: g2's s3, isCurrent=false
      expect(payload.rows.length, 2);
      final r0 = payload.rows[0] as Map<String, dynamic>;
      final r1 = payload.rows[1] as Map<String, dynamic>;
      expect(r0['goalId'], 'g1');
      expect(r0['subtaskId'], 's2');
      expect(r0['isCurrent'], isTrue);
      expect(r1['goalId'], 'g2');
      expect(r1['subtaskId'], 's3');
      expect(r1['isCurrent'], isFalse);
    });
  });
}
