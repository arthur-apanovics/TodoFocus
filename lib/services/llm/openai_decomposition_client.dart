import 'dart:convert';
import '../../models/enums.dart';
import 'decomposition_client.dart';
import 'llm_client.dart';

// Adapts LlmClient into a DecompositionClient by supplying the system prompt,
// JSON schema constraint, and output parsing. Extracted from GoalDecompositionService
// so the service stays provider-agnostic.
class OpenAiDecompositionClient implements DecompositionClient {
  // Default system prompt — count range is appended dynamically at call time
  // based on the goal's difficulty and the configured min/max values.
  static const defaultSystemPrompt =
      'Break the goal into short, concrete, ADHD friendly, actionable steps. '
      'Each step must be a single sentence that is very easy to action.';

  static const defaultBreakdownPrompt =
      'The user has ADHD and is feeling stuck on a subtask because it still feels too big. '
      'Break it down further into 1–3 even smaller, more concrete, immediately actionable steps. '
      'Each step must be a single sentence that requires almost no decision-making to start.';

  final LlmClient _llm;
  final String systemPrompt;
  final String breakdownPrompt;

  // Per-difficulty subtask count bounds — configurable in LLM settings.
  final int easyMin;
  final int easyMax;
  final int hardMin;
  final int hardMax;
  final int impossibleMin;
  final int impossibleMax;

  OpenAiDecompositionClient(
    this._llm, {
    this.systemPrompt = defaultSystemPrompt,
    this.breakdownPrompt = defaultBreakdownPrompt,
    this.easyMin = 3,
    this.easyMax = 6,
    this.hardMin = 10,
    this.hardMax = 20,
    this.impossibleMin = 30,
    this.impossibleMax = 50,
  });

  // Tighter bounds than decompose — breakdown turns one overwhelming subtask
  // into 1–3 even smaller steps. More than 3 defeats the purpose.
  static const _breakdownSchema = {
    'type': 'array',
    'items': {'type': 'string', 'minLength': 3, 'maxLength': 120},
    'minItems': 1,
    'maxItems': 3,
  };

  (int, int) _rangesFor(GoalDifficulty? difficulty) => switch (difficulty) {
    GoalDifficulty.easy || null => (easyMin, easyMax),
    GoalDifficulty.hard => (hardMin, hardMax),
    GoalDifficulty.impossible => (impossibleMin, impossibleMax),
  };

  Map<String, dynamic> _schemaFor(int min, int max) => {
    'type': 'array',
    'items': {'type': 'string', 'minLength': 3, 'maxLength': 120},
    'minItems': min,
    'maxItems': max,
  };

  @override
  Future<List<String>> decompose(
    String title, {
    String? description,
    String? additionalInstructions,
    GoalDifficulty? difficulty,
    List<String>? completedSteps,
  }) async {
    final (min, max) = _rangesFor(difficulty);
    final effectiveSystem =
        '$systemPrompt\n\nGenerate between $min and $max steps.';
    var user = description?.isNotEmpty == true
        ? 'Goal: "$title". Context: $description'
        : 'Goal: "$title"';
    if (completedSteps?.isNotEmpty == true) {
      final numbered = completedSteps!
          .asMap()
          .entries
          .map((e) => '${e.key + 1}. ${e.value}')
          .join('\n');
      user =
          '$user\n\nSteps already completed (do not repeat these, generate only the remaining steps):\n$numbered';
    }
    if (additionalInstructions?.isNotEmpty == true) {
      user = '$user\n\nAdditional instructions: $additionalInstructions';
    }
    final raw = await _llm.complete(
      effectiveSystem,
      user,
      responseSchema: _schemaFor(min, max),
    );
    return _parseJsonArray(raw);
  }

  @override
  Future<List<String>> breakdown(
    String subtaskDescription, {
    String? additionalInstructions,
    GoalDifficulty? difficulty,
  }) async {
    var user = 'Subtask: "$subtaskDescription"';
    if (additionalInstructions?.isNotEmpty == true) {
      user = '$user\n\nAdditional instructions: $additionalInstructions';
    }
    // When difficulty is provided, use the configured count ranges so the user
    // gets more granular steps for hard/impossible tasks.
    final Map<String, dynamic> schema;
    if (difficulty != null) {
      final (min, max) = _rangesFor(difficulty);
      schema = _schemaFor(min, max);
    } else {
      schema = _breakdownSchema;
    }
    final raw = await _llm.complete(
      breakdownPrompt,
      user,
      responseSchema: schema,
    );
    return _parseJsonArray(raw);
  }

  // System prompt for icon suggestion — the name list is the bulk of the
  // tokens (~900) and is identical across all calls, so providers that support
  // prompt caching (Anthropic, OpenAI) only charge for it once.
  static String _iconSystemPrompt(List<String> iconNames) =>
      'You select icons for goals. '
      'Reply with the single best matching icon name from the list below. '
      'Output only the name, nothing else.\n'
      'Icons: ${iconNames.join(',')}';

  @override
  Future<String?> suggestIcon(String goalTitle, List<String> iconNames) async {
    if (iconNames.isEmpty) return null;
    try {
      final raw = await _llm.complete(
        _iconSystemPrompt(iconNames),
        goalTitle,
        responseSchema: {'type': 'string'},
      );
      final name = raw.trim().replaceAll('"', '');
      return iconNames.contains(name) ? name : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<String?>> suggestIconBulk(
      List<String> goalTitles, List<String> iconNames) async {
    if (goalTitles.isEmpty) return [];
    if (iconNames.isEmpty) return List.filled(goalTitles.length, null);
    try {
      // Same system prompt as suggestIcon → hits the same prompt cache.
      final raw = await _llm.complete(
        _iconSystemPrompt(iconNames),
        'Return a JSON array of icon names — one per goal, same order.\n'
            '${jsonEncode(goalTitles)}',
        responseSchema: {
          'type': 'array',
          'items': {'type': 'string'},
          'minItems': goalTitles.length,
          'maxItems': goalTitles.length,
        },
      );
      final parsed = _parseJsonArray(raw);
      return List.generate(goalTitles.length, (i) {
        if (i >= parsed.length) return null;
        final name = parsed[i].trim().replaceAll('"', '');
        return iconNames.contains(name) ? name : null;
      });
    } catch (_) {
      return List.filled(goalTitles.length, null);
    }
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
