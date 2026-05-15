import 'dart:convert';
import 'decomposition_client.dart';
import 'llm_client.dart';

// Adapts LlmClient into a DecompositionClient by supplying the system prompt,
// JSON schema constraint, and output parsing. Extracted from GoalDecompositionService
// so the service stays provider-agnostic.
class OpenAiDecompositionClient implements DecompositionClient {
  static const defaultSystemPrompt =
      'Break the goal into 3–6 short, concrete, ADHD friendly, actionable steps. '
      'Each step must be a single sentence that is very easy to action.';

  static const defaultBreakdownPrompt =
      'The user has ADHD and is feeling stuck on a subtask because it still feels too big. '
      'Break it down further into 1–3 even smaller, more concrete, immediately actionable steps. '
      'Each step must be a single sentence that requires almost no decision-making to start.';

  final LlmClient _llm;
  final String systemPrompt;
  final String breakdownPrompt;

  OpenAiDecompositionClient(
    this._llm, {
    this.systemPrompt = defaultSystemPrompt,
    this.breakdownPrompt = defaultBreakdownPrompt,
  });

  static const _subtasksSchema = {
    'type': 'array',
    'items': {'type': 'string', 'minLength': 3, 'maxLength': 120},
    'minItems': 2,
    'maxItems': 10,
  };

  // Tighter bounds than decompose — breakdown turns one overwhelming subtask
  // into 1–3 even smaller steps. More than 3 defeats the purpose.
  static const _breakdownSchema = {
    'type': 'array',
    'items': {'type': 'string', 'minLength': 3, 'maxLength': 120},
    'minItems': 1,
    'maxItems': 3,
  };

  @override
  Future<List<String>> decompose(String title, {String? description, String? additionalInstructions}) async {
    var user = description?.isNotEmpty == true
        ? 'Goal: "$title". Context: $description'
        : 'Goal: "$title"';
    if (additionalInstructions?.isNotEmpty == true) {
      user = '$user\n\nAdditional instructions: $additionalInstructions';
    }
    final raw = await _llm.complete(systemPrompt, user, responseSchema: _subtasksSchema);
    return _parseJsonArray(raw);
  }

  @override
  Future<List<String>> breakdown(String subtaskDescription, {String? additionalInstructions}) async {
    var user = 'Subtask: "$subtaskDescription"';
    if (additionalInstructions?.isNotEmpty == true) {
      user = '$user\n\nAdditional instructions: $additionalInstructions';
    }
    final raw = await _llm.complete(breakdownPrompt, user, responseSchema: _breakdownSchema);
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
      try {
        final extracted = jsonDecode(match.group(0)!);
        if (extracted is List) return _toStringList(extracted);
      } catch (_) {}
    }

    final preview = raw.length > 500 ? '${raw.substring(0, 500)}…' : raw;
    throw FormatException(
        'LLM response contained no valid JSON array.'
        '\n\nRaw response:\n$preview');
  }

  List<String> _toStringList(List<dynamic> list) {
    final strings = list.whereType<String>().toList();
    if (strings.isEmpty) {
      throw const FormatException('JSON array contained no strings');
    }
    return strings;
  }
}
