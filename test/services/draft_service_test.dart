import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/models/enums.dart';
import 'package:todo_app/services/draft_service.dart';

void main() {
  // -------------------------------------------------------------------------
  // New goal draft
  // -------------------------------------------------------------------------

  group('DraftService — new goal draft', () {
    test('starts empty and hasNewGoalDraft is false', () {
      final s = DraftService();
      expect(s.newGoalTitle, '');
      expect(s.newGoalDescription, '');
      expect(s.newGoalDueDate, isNull);
      expect(s.newGoalDifficulty, GoalDifficulty.easy);
      expect(s.hasNewGoalDraft, isFalse);
    });

    test('saveNewGoal updates all fields', () {
      final s = DraftService();
      final date = DateTime(2026, 1, 1);
      s.saveNewGoal(
        title: 'Learn Rust',
        description: 'systems programming',
        dueDate: date,
        difficulty: GoalDifficulty.hard,
      );
      expect(s.newGoalTitle, 'Learn Rust');
      expect(s.newGoalDescription, 'systems programming');
      expect(s.newGoalDueDate, date);
      expect(s.newGoalDifficulty, GoalDifficulty.hard);
    });

    test('hasNewGoalDraft is true when title is non-empty', () {
      final s = DraftService()
        ..saveNewGoal(
          title: 'x',
          description: '',
          dueDate: null,
          difficulty: GoalDifficulty.easy,
        );
      expect(s.hasNewGoalDraft, isTrue);
    });

    test('hasNewGoalDraft is true when difficulty is non-default', () {
      final s = DraftService()
        ..saveNewGoal(
          title: '',
          description: '',
          dueDate: null,
          difficulty: GoalDifficulty.impossible,
        );
      expect(s.hasNewGoalDraft, isTrue);
    });

    test('clearNewGoal resets all fields to defaults', () {
      final s = DraftService();
      s.saveNewGoal(
        title: 'Test',
        description: 'Desc',
        dueDate: DateTime.now(),
        difficulty: GoalDifficulty.hard,
      );
      s.clearNewGoal();
      expect(s.newGoalTitle, '');
      expect(s.newGoalDescription, '');
      expect(s.newGoalDueDate, isNull);
      expect(s.newGoalDifficulty, GoalDifficulty.easy);
      expect(s.hasNewGoalDraft, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // Bulk re-decompose instructions
  // -------------------------------------------------------------------------

  group('DraftService — bulk re-decompose instructions', () {
    test('starts empty', () {
      expect(DraftService().bulkRedecomposeInstructions, '');
    });

    test('save and retrieve', () {
      final s = DraftService();
      s.saveBulkRedecomposeInstructions('be concise');
      expect(s.bulkRedecomposeInstructions, 'be concise');
    });

    test('clear resets to empty', () {
      final s = DraftService();
      s.saveBulkRedecomposeInstructions('be concise');
      s.clearBulkRedecomposeInstructions();
      expect(s.bulkRedecomposeInstructions, '');
    });
  });

  // -------------------------------------------------------------------------
  // Re-decompose instructions
  // -------------------------------------------------------------------------

  group('DraftService — re-decompose instructions', () {
    test('returns empty string when no draft exists for a goalId', () {
      expect(DraftService().redecomposeInstructions('g1'), '');
    });

    test('saves and retrieves instructions per goalId', () {
      final s = DraftService();
      s.saveRedecomposeInstructions('g1', 'focus on research');
      expect(s.redecomposeInstructions('g1'), 'focus on research');
    });

    test('each goalId is independent', () {
      final s = DraftService();
      s.saveRedecomposeInstructions('g1', 'alpha');
      s.saveRedecomposeInstructions('g2', 'beta');
      expect(s.redecomposeInstructions('g1'), 'alpha');
      expect(s.redecomposeInstructions('g2'), 'beta');
    });

    test('clearRedecomposeInstructions removes the entry', () {
      final s = DraftService();
      s.saveRedecomposeInstructions('g1', 'focus on research');
      s.clearRedecomposeInstructions('g1');
      expect(s.redecomposeInstructions('g1'), '');
    });

    test('clearing one goalId does not affect another', () {
      final s = DraftService();
      s.saveRedecomposeInstructions('g1', 'alpha');
      s.saveRedecomposeInstructions('g2', 'beta');
      s.clearRedecomposeInstructions('g1');
      expect(s.redecomposeInstructions('g2'), 'beta');
    });
  });

  // -------------------------------------------------------------------------
  // Subtask breakdown instructions
  // -------------------------------------------------------------------------

  group('DraftService — breakdown instructions', () {
    test('returns empty string when no draft exists for a subtaskId', () {
      expect(DraftService().breakdownInstructions('s1'), '');
    });

    test('saves and retrieves instructions per subtaskId', () {
      final s = DraftService();
      s.saveBreakdownInstructions('s1', 'keep steps under 5 min');
      expect(s.breakdownInstructions('s1'), 'keep steps under 5 min');
    });

    test('each subtaskId is independent', () {
      final s = DraftService();
      s.saveBreakdownInstructions('s1', 'alpha');
      s.saveBreakdownInstructions('s2', 'beta');
      expect(s.breakdownInstructions('s1'), 'alpha');
      expect(s.breakdownInstructions('s2'), 'beta');
    });

    test('clearBreakdownInstructions removes the entry', () {
      final s = DraftService();
      s.saveBreakdownInstructions('s1', 'keep steps under 5 min');
      s.clearBreakdownInstructions('s1');
      expect(s.breakdownInstructions('s1'), '');
    });

    test('clearing one subtaskId does not affect another', () {
      final s = DraftService();
      s.saveBreakdownInstructions('s1', 'alpha');
      s.saveBreakdownInstructions('s2', 'beta');
      s.clearBreakdownInstructions('s1');
      expect(s.breakdownInstructions('s2'), 'beta');
    });

    test('overwriting a draft replaces the previous value', () {
      final s = DraftService();
      s.saveBreakdownInstructions('s1', 'first');
      s.saveBreakdownInstructions('s1', 'second');
      expect(s.breakdownInstructions('s1'), 'second');
    });
  });
}
