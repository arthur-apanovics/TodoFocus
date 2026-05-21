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
  });
}
