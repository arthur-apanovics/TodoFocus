import '../../models/enums.dart';

abstract interface class DecompositionClient {
  /// Decomposes [title] into a list of actionable subtask descriptions.
  /// [description] is optional context; providers that don't support it ignore it.
  /// [difficulty] controls how many subtasks are generated; defaults to easy.
  /// Throws on network error or unrecoverable response — callers handle fallback.
  Future<List<String>> decompose(
    String title, {
    String? description,
    String? additionalInstructions,
    GoalDifficulty? difficulty,
    List<String>? completedSteps,
  });

  /// Breaks an existing subtask down further into 1–3 smaller steps.
  /// Used when a subtask itself feels overwhelming to start.
  /// [difficulty] controls granularity; providers that don't support it ignore it.
  /// Throws on network error or unrecoverable response — callers handle fallback.
  Future<List<String>> breakdown(
    String subtaskDescription, {
    String? additionalInstructions,
    GoalDifficulty? difficulty,
  });
}
