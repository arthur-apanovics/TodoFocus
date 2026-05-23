/// A single step returned by the decomposition LLM (or fabricated by the
/// keyword fallback / manual user input). Carries the description plus an
/// optional time estimate in minutes — null when the source couldn't or
/// chose not to provide one (keyword scaffolds, manual subtask entry).
class DecomposedStep {
  final String description;
  final int? estimatedMinutes;

  const DecomposedStep(this.description, {this.estimatedMinutes});

  /// Convenience for the keyword-fallback paths that only have a description.
  factory DecomposedStep.text(String description) =>
      DecomposedStep(description);
}
