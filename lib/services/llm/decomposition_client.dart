abstract interface class DecompositionClient {
  /// Decomposes [title] into a list of actionable subtask descriptions.
  /// [description] is optional context; providers that don't support it ignore it.
  /// Throws on network error or unrecoverable response — callers handle fallback.
  Future<List<String>> decompose(String title, {String? description});

  /// Breaks an existing subtask down further into 1–3 smaller steps.
  /// Used when a subtask itself feels overwhelming to start.
  /// Throws on network error or unrecoverable response — callers handle fallback.
  Future<List<String>> breakdown(String subtaskDescription);
}
