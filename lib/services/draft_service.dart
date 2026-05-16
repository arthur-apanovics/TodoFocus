import '../models/enums.dart';

/// In-memory holder for transient user input that should survive a sheet or
/// dialog being dismissed but not outlive the process. Three independent
/// buckets:
///
/// - New-goal form fields (single, global)
/// - Re-decompose instructions, keyed by goalId
/// - Subtask breakdown instructions, keyed by subtaskId
///
/// Consumers read from the draft when a sheet opens and write back when it
/// closes (or on every keystroke). After a successful submission callers
/// clear the relevant bucket so stale data does not resurface.
class DraftService {
  // ---------------------------------------------------------------------------
  // New goal draft
  // ---------------------------------------------------------------------------

  String newGoalTitle = '';
  String newGoalDescription = '';
  DateTime? newGoalDueDate;
  GoalDifficulty newGoalDifficulty = GoalDifficulty.easy;

  bool get hasNewGoalDraft =>
      newGoalTitle.isNotEmpty ||
      newGoalDescription.isNotEmpty ||
      newGoalDueDate != null ||
      newGoalDifficulty != GoalDifficulty.easy;

  void saveNewGoal({
    required String title,
    required String description,
    required DateTime? dueDate,
    required GoalDifficulty difficulty,
  }) {
    newGoalTitle = title;
    newGoalDescription = description;
    newGoalDueDate = dueDate;
    newGoalDifficulty = difficulty;
  }

  void clearNewGoal() {
    newGoalTitle = '';
    newGoalDescription = '';
    newGoalDueDate = null;
    newGoalDifficulty = GoalDifficulty.easy;
  }

  // ---------------------------------------------------------------------------
  // Bulk re-decompose instructions (shared across all selected goals)
  // ---------------------------------------------------------------------------

  String bulkRedecomposeInstructions = '';

  void saveBulkRedecomposeInstructions(String instructions) {
    bulkRedecomposeInstructions = instructions;
  }

  void clearBulkRedecomposeInstructions() {
    bulkRedecomposeInstructions = '';
  }

  // ---------------------------------------------------------------------------
  // Re-decompose instructions (per goalId)
  // ---------------------------------------------------------------------------

  final _redecomposeInstructions = <String, String>{};

  String redecomposeInstructions(String goalId) =>
      _redecomposeInstructions[goalId] ?? '';

  void saveRedecomposeInstructions(String goalId, String instructions) {
    _redecomposeInstructions[goalId] = instructions;
  }

  void clearRedecomposeInstructions(String goalId) {
    _redecomposeInstructions.remove(goalId);
  }

  // ---------------------------------------------------------------------------
  // Subtask breakdown instructions (per subtaskId)
  // ---------------------------------------------------------------------------

  final _breakdownInstructions = <String, String>{};

  String breakdownInstructions(String subtaskId) =>
      _breakdownInstructions[subtaskId] ?? '';

  void saveBreakdownInstructions(String subtaskId, String instructions) {
    _breakdownInstructions[subtaskId] = instructions;
  }

  void clearBreakdownInstructions(String subtaskId) {
    _breakdownInstructions.remove(subtaskId);
  }
}
