import 'dart:convert';
import 'decomposition_client.dart';
import 'llm_client.dart';

// Adapts LlmClient into a DecompositionClient by supplying the system prompt,
// JSON schema constraint, and output parsing. Extracted from GoalDecompositionService
// so the service stays provider-agnostic.
class OpenAiDecompositionClient implements DecompositionClient {
  final LlmClient _llm;

  OpenAiDecompositionClient(this._llm);

  static const _subtasksSchema = {
    'type': 'array',
    'items': {'type': 'string', 'minLength': 3, 'maxLength': 120},
    'minItems': 2,
    'maxItems': 10,
  };

  @override
  Future<List<String>> decompose(String title, {String? description}) async {
    const system =
        'Break the goal into 3–6 short, concrete, ADHD friendly, actionable steps. '
        'Each step must be a single sentence that is very easy to action.';

    final user = description?.isNotEmpty == true
        ? 'Goal: "$title". Context: $description'
        : 'Goal: "$title"';

    final raw = await _llm.complete(system, user, responseSchema: _subtasksSchema);
    return _parseJsonArray(raw);
  }

  // Tolerates markdown fences, leading prose, and other common LLM slop.
  // Throws FormatException when no valid array can be extracted.
  List<String> _parseJsonArray(String raw) {
    var cleaned = raw.replaceAll(RegExp(r'```[a-zA-Z]*\n?'), '').trim();

    try {
      final decoded = jsonDecode(cleaned);
      if (decoded is List) return _toStringList(decoded);
    } catch (_) {}

    final match = RegExp(r'\[.*?\]', dotAll: true).firstMatch(cleaned);
    if (match != null) {
      final extracted = jsonDecode(match.group(0)!);
      if (extracted is List) return _toStringList(extracted);
    }

    throw const FormatException('LLM response contained no valid JSON array');
  }

  List<String> _toStringList(List<dynamic> list) {
    final strings = list.whereType<String>().toList();
    if (strings.isEmpty) {
      throw const FormatException('JSON array contained no strings');
    }
    return strings;
  }
}
