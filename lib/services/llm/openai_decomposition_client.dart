import 'dart:convert';
import '../../models/enums.dart';
import 'decomposed_step.dart';
import 'decomposition_client.dart';
import 'llm_client.dart';

// Adapts LlmClient into a DecompositionClient by supplying the system prompt,
// JSON schema constraint, and output parsing. Extracted from GoalDecompositionService
// so the service stays provider-agnostic.
class OpenAiDecompositionClient implements DecompositionClient {
  // Style-only system prompt — describes the kind of steps the user wants.
  // All per-operation instructions (counts, schema, etc.) are injected into
  // the user message so this stays stable across calls and benefits from
  // provider-side prompt caching.
  //
  // IMPORTANT: this is the *user-editable* fragment. The fixed instruction
  // that pins the JSON shape and the time-estimate requirement is held in
  // [_estimateAndSchemaInstruction] below and concatenated at request time —
  // a user can rewrite the style guidance without breaking the response
  // contract that drives the rest of the app.
  static const defaultSystemPrompt =
      'You are a task planning assistant for people with ADHD. '
      'Generate short, concrete, immediately actionable steps. '
      'Each step is a single sentence requiring almost no decision-making to start.';

  /// Non-editable suffix appended to every system prompt before sending. It
  /// pins the response schema and the time-estimate semantics so a user who
  /// customises [systemPrompt] can't accidentally break either: removing
  /// the "give time estimates" line used to leave the model guessing, and
  /// it might emit `0` or omit the field entirely (which the JSON-schema
  /// validator then rejected). Keeping this fragment server-managed means
  /// the app's downstream estimate-aware UI always has something to render.
  static const String _estimateAndSchemaInstruction =
      'For every step, provide a realistic time estimate in minutes for how '
      'long that single step alone will take an average adult — be honest, '
      'not aspirational. Typical values are 5–60 minutes per step. '
      'Always respond with a JSON array of {"description": string, '
      '"estimated_minutes": integer} objects, nothing else.';

  /// Combines the user-editable [systemPrompt] with the fixed
  /// estimate/schema instruction.
  String get _effectiveSystemPrompt =>
      '$systemPrompt\n\n$_estimateAndSchemaInstruction';

  final LlmClient _llm;
  final String systemPrompt;

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
    this.easyMin = 3,
    this.easyMax = 6,
    this.hardMin = 10,
    this.hardMax = 20,
    this.impossibleMin = 30,
    this.impossibleMax = 50,
  });

  // Single object shape reused across all schemas — keeps the parser uniform.
  static const _stepItemSchema = {
    'type': 'object',
    'properties': {
      'description': {'type': 'string', 'minLength': 3, 'maxLength': 120},
      'estimated_minutes': {'type': 'integer', 'minimum': 1, 'maximum': 480},
    },
    'required': ['description', 'estimated_minutes'],
    'additionalProperties': false,
  };

  // Tighter bounds than decompose — breakdown turns one overwhelming subtask
  // into a handful of even smaller steps. More than 5 defeats the purpose.
  static const _breakdownSchema = {
    'type': 'array',
    'items': _stepItemSchema,
    'minItems': 1,
    'maxItems': 5,
  };

  // Fixed schema for addSteps — always 1–5 new steps regardless of difficulty.
  // The user is adding specific things, not decomposing an entire goal.
  static const _addStepsSchema = {
    'type': 'array',
    'items': _stepItemSchema,
    'minItems': 1,
    'maxItems': 5,
  };

  // Estimate-only schema — flat array of integers, one per input description.
  static const _estimateSchema = {
    'type': 'array',
    'items': {'type': 'integer', 'minimum': 1, 'maximum': 480},
  };

  (int, int) _rangesFor(GoalDifficulty? difficulty) => switch (difficulty) {
    GoalDifficulty.easy || null => (easyMin, easyMax),
    GoalDifficulty.hard => (hardMin, hardMax),
    GoalDifficulty.impossible => (impossibleMin, impossibleMax),
  };

  Map<String, dynamic> _schemaFor(int min, int max) => {
    'type': 'array',
    'items': _stepItemSchema,
    'minItems': min,
    'maxItems': max,
  };

  @override
  Future<List<DecomposedStep>> decompose(
    String title, {
    String? description,
    String? additionalInstructions,
    GoalDifficulty? difficulty,
    List<String>? completedSteps,
  }) async {
    final (min, max) = _rangesFor(difficulty);
    final parts = <String>[
      'Generate between $min and $max steps for this goal: "$title". '
          'Each step must include a realistic time estimate in minutes.',
    ];
    if (description?.isNotEmpty == true) {
      parts.add('Context: $description');
    }
    if (completedSteps?.isNotEmpty == true) {
      final numbered = completedSteps!
          .asMap()
          .entries
          .map((e) => '${e.key + 1}. ${e.value}')
          .join('\n');
      parts.add(
          'Steps already completed (do not repeat these, generate only the remaining steps):\n$numbered');
    }
    if (additionalInstructions?.isNotEmpty == true) {
      parts.add('Additional instructions: $additionalInstructions');
    }
    final raw = await _llm.complete(
      _effectiveSystemPrompt,
      parts.join('\n\n'),
      responseSchema: _schemaFor(min, max),
    );
    return _parseSteps(raw);
  }

  @override
  Future<List<DecomposedStep>> modify(
    String title, {
    String? description,
    String? additionalInstructions,
    GoalDifficulty? difficulty,
    required List<String> pendingSteps,
    List<String>? completedSteps,
  }) async {
    final (min, max) = _rangesFor(difficulty);
    final parts = <String>[
      'Modify the pending steps for this goal: "$title".\n'
          'Add, remove, split, rephrase, or reorder them as needed. '
          'Each returned step must include a realistic time estimate in minutes. '
          'Return only the updated pending steps — do not include completed steps.',
    ];
    if (description?.isNotEmpty == true) {
      parts.add('Context: $description');
    }
    if (completedSteps?.isNotEmpty == true) {
      final numbered = completedSteps!
          .asMap()
          .entries
          .map((e) => '${e.key + 1}. ${e.value}')
          .join('\n');
      parts.add(
          'Already completed (for context only — do not include these in your response):\n$numbered');
    }
    final pendingNumbered = pendingSteps
        .asMap()
        .entries
        .map((e) => '${e.key + 1}. ${e.value}')
        .join('\n');
    parts.add('Current pending steps to modify:\n$pendingNumbered');
    if (additionalInstructions?.isNotEmpty == true) {
      parts.add('Instructions: $additionalInstructions');
    }
    final raw = await _llm.complete(
      _effectiveSystemPrompt,
      parts.join('\n\n'),
      responseSchema: _schemaFor(min, max),
    );
    return _parseSteps(raw);
  }

  @override
  Future<List<DecomposedStep>> breakdown(
    String subtaskDescription, {
    String? additionalInstructions,
    GoalDifficulty? difficulty,
    String? goalTitle,
    String? goalDescription,
    List<String>? completedSteps,
    List<String>? otherPendingSteps,
  }) async {
    // When difficulty is provided, use the configured count ranges so the user
    // gets more granular steps for hard/impossible tasks.
    final Map<String, dynamic> schema;
    final int min;
    final int max;
    if (difficulty != null) {
      (min, max) = _rangesFor(difficulty);
      schema = _schemaFor(min, max);
    } else {
      min = 1;
      max = 5;
      schema = _breakdownSchema;
    }

    final parts = <String>[
      'Break this subtask into $min–$max smaller, more concrete, immediately actionable steps. '
          'Each step must include a realistic time estimate in minutes. '
          'The user is stuck because the step feels too big.',
    ];
    if (goalTitle?.isNotEmpty == true) {
      final goalLine = goalDescription?.isNotEmpty == true
          ? 'Goal: "$goalTitle" — $goalDescription'
          : 'Goal: "$goalTitle"';
      parts.add(goalLine);
    }
    if (completedSteps?.isNotEmpty == true) {
      final numbered = completedSteps!
          .asMap()
          .entries
          .map((e) => '${e.key + 1}. ${e.value}')
          .join('\n');
      parts.add('Already completed:\n$numbered');
    }
    if (otherPendingSteps?.isNotEmpty == true) {
      final numbered = otherPendingSteps!
          .asMap()
          .entries
          .map((e) => '${e.key + 1}. ${e.value}')
          .join('\n');
      parts.add('Other upcoming steps (for context, do not repeat):\n$numbered');
    }
    parts.add('Subtask to break down: "$subtaskDescription"');
    if (additionalInstructions?.isNotEmpty == true) {
      parts.add('Additional instructions: $additionalInstructions');
    }

    final raw = await _llm.complete(
      _effectiveSystemPrompt,
      parts.join('\n\n'),
      responseSchema: schema,
    );
    return _parseSteps(raw);
  }

  @override
  Future<List<DecomposedStep>> addSteps(
    String title, {
    String? description,
    String? userPrompt,
    GoalDifficulty? difficulty,
    List<String>? existingPendingSteps,
    List<String>? existingCompletedSteps,
  }) async {
    final parts = <String>[
      'Generate 1–5 new steps to ADD to this goal\'s existing plan. '
          'Each step must include a realistic time estimate in minutes. '
          'Do not repeat, rephrase, or include any existing steps. '
          'Generate only the new additions requested.',
    ];
    if (description?.isNotEmpty == true) {
      parts.add('Goal: "$title" — $description');
    } else {
      parts.add('Goal: "$title"');
    }
    if (existingCompletedSteps?.isNotEmpty == true) {
      final numbered = existingCompletedSteps!
          .asMap()
          .entries
          .map((e) => '${e.key + 1}. ${e.value}')
          .join('\n');
      parts.add('Already completed:\n$numbered');
    }
    if (existingPendingSteps?.isNotEmpty == true) {
      final numbered = existingPendingSteps!
          .asMap()
          .entries
          .map((e) => '${e.key + 1}. ${e.value}')
          .join('\n');
      parts.add('Existing pending steps (do not repeat these):\n$numbered');
    }
    if (userPrompt?.isNotEmpty == true) {
      parts.add('Add steps for: $userPrompt');
    }
    final raw = await _llm.complete(
      _effectiveSystemPrompt,
      parts.join('\n\n'),
      responseSchema: _addStepsSchema,
    );
    return _parseSteps(raw);
  }

  @override
  Future<List<int?>> estimate(
    List<String> descriptions, {
    String? goalTitle,
    String? goalDescription,
  }) async {
    if (descriptions.isEmpty) return const [];
    // Distinct system prompt so the model returns plain integers rather than
    // step-object structures. Kept stable for prompt caching.
    const estimateSystemPrompt =
        'You assign realistic time estimates to task steps for people with ADHD. '
        'Reply with a JSON array of integers — one minute estimate per input step, '
        'in the same order. Be honest, not aspirational. Typical values are 5–60 '
        'minutes per step. Output only the JSON array.';

    final parts = <String>[];
    if (goalTitle?.isNotEmpty == true) {
      final goalLine = goalDescription?.isNotEmpty == true
          ? 'Goal: "$goalTitle" — $goalDescription'
          : 'Goal: "$goalTitle"';
      parts.add(goalLine);
    }
    final numbered = descriptions
        .asMap()
        .entries
        .map((e) => '${e.key + 1}. ${e.value}')
        .join('\n');
    parts.add(
        'Estimate minutes for each of the following steps (return ${descriptions.length} integers in the same order):\n$numbered');

    final raw = await _llm.complete(
      estimateSystemPrompt,
      parts.join('\n\n'),
      responseSchema: {
        ..._estimateSchema,
        'minItems': descriptions.length,
        'maxItems': descriptions.length,
      },
    );

    final ints = _parseIntArray(raw);
    // Pad / trim to match the input length — defensive against models that
    // ignore the cardinality hint.
    final out = List<int?>.filled(descriptions.length, null);
    for (var i = 0; i < descriptions.length && i < ints.length; i++) {
      out[i] = ints[i];
    }
    return out;
  }

  // Schema for nudge responses — a single object with the nudge message.
  static const _nudgeSchema = {
    'type': 'object',
    'properties': {
      'message': {'type': 'string', 'minLength': 10, 'maxLength': 250},
    },
    'required': ['message'],
    'additionalProperties': false,
  };

  @override
  Future<String?> generateNudge(
    String goalTitle, {
    String? goalDescription,
    required String currentSubtask,
    String? nextSubtask,
    required Duration staleDuration,
    required String promptTemplate,
  }) async {
    final systemPrompt =
        '$promptTemplate\n\nRespond with JSON: {"message": "your nudge here"}';
    final parts = [
      'Goal: "$goalTitle"',
      if (goalDescription?.isNotEmpty == true) 'Description: $goalDescription',
      'Current step: "$currentSubtask"',
      if (nextSubtask?.isNotEmpty == true) 'Next step: "$nextSubtask"',
      'Idle for: ${_formatStaleDuration(staleDuration)}',
      'Write a nudge.',
    ];
    final raw = await _llm.complete(
      systemPrompt,
      parts.join('\n'),
      responseSchema: _nudgeSchema,
    );
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final msg = (json['message'] as String?)?.trim();
      return (msg == null || msg.isEmpty) ? null : msg;
    } catch (_) {
      final trimmed = raw.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
  }

  String _formatStaleDuration(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes} minutes';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return m == 0 ? '$h hour${h == 1 ? '' : 's'}' : '$h hour${h == 1 ? '' : 's'} $m minutes';
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
      final parsed = _parseStringArray(raw);
      return List.generate(goalTitles.length, (i) {
        if (i >= parsed.length) return null;
        final name = parsed[i].trim().replaceAll('"', '');
        return iconNames.contains(name) ? name : null;
      });
    } catch (_) {
      return List.filled(goalTitles.length, null);
    }
  }

  // Tolerant decoder for step-array responses. Accepts:
  //   • [{description, estimated_minutes}, ...] — the schema-conformant case
  //   • ["plain string", ...]                   — older / drifted responses
  //   • Mixed arrays                            — falls back to string-only
  // Throws FormatException when no valid array can be extracted.
  List<DecomposedStep> _parseSteps(String raw) {
    final list = _extractJsonArray(raw);
    final out = <DecomposedStep>[];
    for (final item in list) {
      if (item is Map) {
        final desc = item['description'];
        if (desc is! String) continue;
        final mins = item['estimated_minutes'];
        out.add(DecomposedStep(
          desc,
          estimatedMinutes: mins is int
              ? mins
              : (mins is num ? mins.round() : null),
        ));
      } else if (item is String) {
        out.add(DecomposedStep(item));
      }
    }
    if (out.isEmpty) {
      throw const FormatException('JSON array contained no usable steps');
    }
    return out;
  }

  List<String> _parseStringArray(String raw) {
    final list = _extractJsonArray(raw);
    final strings = list.whereType<String>().toList();
    if (strings.isEmpty) {
      throw const FormatException('JSON array contained no strings');
    }
    return strings;
  }

  List<int> _parseIntArray(String raw) {
    final list = _extractJsonArray(raw);
    final ints = <int>[];
    for (final item in list) {
      if (item is int) {
        ints.add(item);
      } else if (item is num) {
        ints.add(item.round());
      }
    }
    if (ints.isEmpty) {
      throw const FormatException('JSON array contained no integers');
    }
    return ints;
  }

  // Tolerates markdown fences, leading prose, and other common LLM slop.
  // Returns the first valid JSON array found in [raw], else throws.
  List<dynamic> _extractJsonArray(String raw) {
    var cleaned = raw.replaceAll(RegExp(r'```[a-zA-Z]*\n?'), '').trim();

    try {
      final decoded = jsonDecode(cleaned);
      if (decoded is List) return decoded;
    } catch (_) {}

    final match = RegExp(r'\[.*\]', dotAll: true).firstMatch(cleaned);
    if (match != null) {
      try {
        final extracted = jsonDecode(match.group(0)!);
        if (extracted is List) return extracted;
      } catch (_) {}
    }

    final preview = raw.length > 500 ? '${raw.substring(0, 500)}…' : raw;
    throw FormatException(
        'LLM response contained no valid JSON array.'
        '\n\nRaw response:\n$preview');
  }
}
