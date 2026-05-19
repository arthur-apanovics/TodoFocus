class LlmConfig {
  final String baseUrl;
  final String model;
  final String? apiKey;
  final Duration timeout;
  final double temperature;

  const LlmConfig({
    required this.baseUrl,
    required this.model,
    this.apiKey,
    this.timeout = const Duration(seconds: 20),
    this.temperature = 0.3,
  });

  // Reads from --dart-define build args; returns null when LLM_BASE_URL is absent,
  // which means the decomposition service runs in keyword-only mode.
  //
  // Local dev (Ollama):
  //   flutter run --dart-define=LLM_BASE_URL=http://localhost:11434/v1
  //              --dart-define=LLM_MODEL=llama3.2
  //
  // Production:
  //   flutter run --dart-define=LLM_BASE_URL=https://api.openai.com/v1
  //              --dart-define=LLM_MODEL=gpt-4o-mini
  //              --dart-define=LLM_API_KEY=sk-...
  static LlmConfig? fromEnvironment() {
    // Each value must be bound in a const context — String.fromEnvironment is
    // a const factory and only reads the --dart-define value when invoked as
    // a const expression. Used inline as a non-const call it silently returns
    // the default value (the empty string, or whatever `defaultValue` is set
    // to), which previously caused LLM_API_KEY and LLM_MODEL to be ignored.
    const url = String.fromEnvironment('LLM_BASE_URL');
    if (url.isEmpty) return null;

    const model = String.fromEnvironment('LLM_MODEL', defaultValue: 'llama3.2');
    const apiKey = String.fromEnvironment('LLM_API_KEY');

    return LlmConfig(
      baseUrl: url,
      model: model,
      apiKey: apiKey.isEmpty ? null : apiKey,
    );
  }
}
