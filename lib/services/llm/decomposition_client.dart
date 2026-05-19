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

  /// Modifies [pendingSteps] in-place according to [additionalInstructions].
  /// [completedSteps] are passed as read-only context so the model can reason
  /// about what has already been done without touching those entries.
  /// Returns only the updated pending steps — completed steps are never
  /// included in the response.
  Future<List<String>> modify(
    String title, {
    String? description,
    String? additionalInstructions,
    GoalDifficulty? difficulty,
    required List<String> pendingSteps,
    List<String>? completedSteps,
  });

  /// Breaks an existing subtask down further into smaller steps.
  /// Used when a subtask feels overwhelming to start.
  /// [difficulty] controls granularity; providers that don't support it ignore it.
  /// Goal context ([goalTitle], [goalDescription], [completedSteps],
  /// [otherPendingSteps]) is forwarded to the model so it can generate steps
  /// that make sense within the broader goal — all are optional.
  /// Throws on network error or unrecoverable response — callers handle fallback.
  Future<List<String>> breakdown(
    String subtaskDescription, {
    String? additionalInstructions,
    GoalDifficulty? difficulty,
    String? goalTitle,
    String? goalDescription,
    List<String>? completedSteps,
    List<String>? otherPendingSteps,
  });

  /// Generates new steps to APPEND to an existing plan based on [userPrompt].
  /// Unlike [decompose], this never replaces existing steps — it only produces
  /// additions. [existingPendingSteps] and [existingCompletedSteps] are passed
  /// as "do not repeat" context. Throws on error — callers handle fallback.
  Future<List<String>> addSteps(
    String title, {
    String? description,
    String? userPrompt,
    GoalDifficulty? difficulty,
    List<String>? existingPendingSteps,
    List<String>? existingCompletedSteps,
  });

  /// Suggests a single icon name from [iconNames] that best represents
  /// [goalTitle]. Returns null when the provider does not support icon
  /// suggestions, the result is not in [iconNames], or the call fails.
  Future<String?> suggestIcon(String goalTitle, List<String> iconNames);

  /// Suggests icon names for multiple goals in a single request.
  /// Returns a list the same length as [goalTitles]; entries not found in
  /// [iconNames] or that failed are null. Implementations that don't support
  /// icon suggestions should return a list of nulls.
  Future<List<String?>> suggestIconBulk(
      List<String> goalTitles, List<String> iconNames);
}
