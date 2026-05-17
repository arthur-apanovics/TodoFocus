import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/models/enums.dart';
import 'package:todo_app/models/goal.dart';
import 'package:todo_app/models/sub_task.dart';
import 'package:todo_app/services/goal_queries.dart';
import 'package:todo_app/services/goal_repository.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Goal makeGoal({
  String id = 'g1',
  GoalStatus status = GoalStatus.active,
  bool isFocusedToday = false,
  List<SubTask>? subtasks,
}) => Goal(
  goalId: id,
  title: 'Goal $id',
  status: status,
  isFocusedToday: isFocusedToday,
  subtasks: subtasks,
);

SubTask pendingSubTask(String id) =>
    SubTask(subtaskId: id, description: 'Step $id');

GoalQueries makeQueries(List<Goal> goals) {
  final repo = InMemoryGoalRepository.empty();
  for (final g in goals) {
    repo.save(g);
  }
  return GoalQueries(repo);
}

void main() {
  // -------------------------------------------------------------------------
  // todayQueue — these tests directly cover bugs found during development
  // -------------------------------------------------------------------------

  group('GoalQueries.todayQueue', () {
    test('excludes goals where isFocusedToday is false', () {
      final q = makeQueries([
        makeGoal(id: 'g1', isFocusedToday: false, subtasks: [pendingSubTask('s1')]),
        makeGoal(id: 'g2', isFocusedToday: true,  subtasks: [pendingSubTask('s2')]),
      ]);
      expect(q.todayQueue.map((g) => g.goalId), ['g2']);
    });

    test('excludes goals with no subtasks', () {
      // Bug: a focused goal with 0 subtasks showed "All 0 steps complete"
      final q = makeQueries([
        makeGoal(id: 'g1', isFocusedToday: true, subtasks: []),
        makeGoal(id: 'g2', isFocusedToday: true, subtasks: [pendingSubTask('s1')]),
      ]);
      expect(q.todayQueue.map((g) => g.goalId), ['g2']);
    });

    test('excludes completed goals', () {
      final q = makeQueries([
        makeGoal(id: 'g1', isFocusedToday: true, status: GoalStatus.completed,
            subtasks: [pendingSubTask('s1')]),
        makeGoal(id: 'g2', isFocusedToday: true, subtasks: [pendingSubTask('s2')]),
      ]);
      expect(q.todayQueue.map((g) => g.goalId), ['g2']);
    });

    test('excludes inbox goals', () {
      final q = makeQueries([
        makeGoal(id: 'g1', isFocusedToday: true, status: GoalStatus.inbox,
            subtasks: [pendingSubTask('s1')]),
        makeGoal(id: 'g2', isFocusedToday: true, subtasks: [pendingSubTask('s2')]),
      ]);
      expect(q.todayQueue.map((g) => g.goalId), ['g2']);
    });

    test('is empty when no goals match all criteria', () {
      final q = makeQueries([
        makeGoal(isFocusedToday: false, subtasks: [pendingSubTask('s1')]),
      ]);
      expect(q.todayQueue, isEmpty);
    });

    test('includes active focused goals with subtasks', () {
      final q = makeQueries([
        makeGoal(id: 'g1', isFocusedToday: true, subtasks: [pendingSubTask('s1')]),
        makeGoal(id: 'g2', isFocusedToday: true, subtasks: [pendingSubTask('s2')]),
      ]);
      expect(q.todayQueue.length, 2);
    });

    test('sorts results by todayOrder ascending', () {
      final later = makeGoal(id: 'later', isFocusedToday: true, subtasks: [pendingSubTask('s1')])
        ..todayOrder = 5;
      final earlier = makeGoal(id: 'earlier', isFocusedToday: true, subtasks: [pendingSubTask('s2')])
        ..todayOrder = 1;
      final middle = makeGoal(id: 'middle', isFocusedToday: true, subtasks: [pendingSubTask('s3')])
        ..todayOrder = 3;
      // Seed in a deliberately wrong order to exercise the sort.
      final q = makeQueries([later, earlier, middle]);
      expect(
        q.todayQueue.map((g) => g.goalId).toList(),
        ['earlier', 'middle', 'later'],
      );
    });
  });

  // -------------------------------------------------------------------------
  // goals — active only (completed/archived have their own getters)
  // -------------------------------------------------------------------------

  group('GoalQueries.goals', () {
    test('excludes inbox goals', () {
      final q = makeQueries([
        makeGoal(id: 'g1', status: GoalStatus.inbox),
        makeGoal(id: 'g2', status: GoalStatus.active),
      ]);
      expect(q.goals.map((g) => g.goalId), ['g2']);
    });

    test('includes active goals', () {
      final q = makeQueries([makeGoal(id: 'g1', status: GoalStatus.active)]);
      expect(q.goals.map((g) => g.goalId), ['g1']);
    });

    test('excludes completed goals', () {
      final q = makeQueries([makeGoal(id: 'g1', status: GoalStatus.completed)]);
      expect(q.goals, isEmpty);
    });

    test('excludes archived goals', () {
      final q = makeQueries([makeGoal(id: 'g1', status: GoalStatus.archived)]);
      expect(q.goals, isEmpty);
    });

    test('is empty when all goals are in inbox', () {
      final q = makeQueries([makeGoal(status: GoalStatus.inbox)]);
      expect(q.goals, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // completedGoals / archivedGoals
  // -------------------------------------------------------------------------

  group('GoalQueries.completedGoals', () {
    test('returns only completed goals', () {
      final q = makeQueries([
        makeGoal(id: 'g1', status: GoalStatus.active),
        makeGoal(id: 'g2', status: GoalStatus.completed),
        makeGoal(id: 'g3', status: GoalStatus.archived),
      ]);
      expect(q.completedGoals.map((g) => g.goalId), ['g2']);
    });

    test('is empty when no goals are completed', () {
      final q = makeQueries([makeGoal(status: GoalStatus.active)]);
      expect(q.completedGoals, isEmpty);
    });
  });

  group('GoalQueries.archivedGoals', () {
    test('returns only archived goals', () {
      final q = makeQueries([
        makeGoal(id: 'g1', status: GoalStatus.active),
        makeGoal(id: 'g2', status: GoalStatus.archived),
      ]);
      expect(q.archivedGoals.map((g) => g.goalId), ['g2']);
    });

    test('is empty when no goals are archived', () {
      final q = makeQueries([makeGoal(status: GoalStatus.active)]);
      expect(q.archivedGoals, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // inbox
  // -------------------------------------------------------------------------

  group('GoalQueries.inbox', () {
    test('contains only inbox goals', () {
      final q = makeQueries([
        makeGoal(id: 'g1', status: GoalStatus.inbox),
        makeGoal(id: 'g2', status: GoalStatus.active),
      ]);
      expect(q.inbox.map((g) => g.goalId), ['g1']);
    });

    test('is empty when no goals are in inbox', () {
      final q = makeQueries([makeGoal(status: GoalStatus.active)]);
      expect(q.inbox, isEmpty);
    });
  });
}
