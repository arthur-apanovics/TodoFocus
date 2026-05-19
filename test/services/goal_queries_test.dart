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
  List<SubTask>? subtasks,
}) => Goal(
  goalId: id,
  title: 'Goal $id',
  status: status,
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
