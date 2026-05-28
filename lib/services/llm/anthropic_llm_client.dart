import 'dart:convert';
import 'package:http/http.dart' as http;
import 'llm_client.dart';

/// Low-level HTTP wrapper for the Anthropic Messages API.
/// Implements [LlmCompletionClient] so it can be used with
/// [OpenAiDecompositionClient] as a drop-in backend.
///
/// Features:
///   - Prompt caching: the system prompt is marked with `cache_control`
///     so Anthropic charges full price only on the first call in a session.
///   - Extended thinking: when [thinkingBudget] > 0 the model reasons
///     internally before producing output. Thinking blocks are stripped
///     from the returned string — callers see only the text response.
class AnthropicLlmClient implements LlmCompletionClient {
  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _anthropicVersion = '2023-06-01';

  final String apiKey;
  final String model;
  final double temperature;
  final Duration timeout;
  // 0 = thinking disabled; otherwise the token budget for internal reasoning.
  // Minimum effective value is 1024 when non-zero.
  final int thinkingBudget;

  final http.Client _http;

  AnthropicLlmClient({
    required this.apiKey,
    required this.model,
    this.temperature = 0.3,
    this.timeout = const Duration(seconds: 120),
    this.thinkingBudget = 0,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  /// Sends a single message to the Anthropic Messages API.
  ///
  /// [responseSchema] is accepted for interface compatibility but ignored —
  /// Anthropic's Messages API has no structured-output mode equivalent to
  /// OpenAI's `response_format`. JSON output is enforced via the prompt
  /// itself (the [_estimateAndSchemaInstruction] in
  /// [OpenAiDecompositionClient] already handles this).
  ///
  /// Prompt caching is applied automatically to the system prompt; on
  /// supported Claude models this reduces latency and cost for repeated
  /// calls with the same system prompt (e.g. the icon suggestion prompt).
  @override
  Future<String> complete(
    String systemPrompt,
    String userPrompt, {
    Map<String, dynamic>? responseSchema,
  }) async {
    final isThinking = thinkingBudget > 0;
    final betaFeatures = <String>[
      'prompt-caching-2024-07-16',
      if (isThinking) 'interleaved-thinking-2025-05-14',
    ];

    final headers = {
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': _anthropicVersion,
      'anthropic-beta': betaFeatures.join(','),
    };

    // max_tokens must exceed thinkingBudget; 4096 is plenty for JSON output.
    final maxTokens = isThinking ? thinkingBudget + 4096 : 4096;

    final Map<String, dynamic> bodyMap = {
      'model': model,
      'max_tokens': maxTokens,
      'system': [
        {
          'type': 'text',
          'text': systemPrompt,
          // Marks the system prompt as cacheable — Anthropic stores it for
          // ~5 minutes so subsequent requests with the same system prompt
          // skip re-processing its tokens.
          'cache_control': {'type': 'ephemeral'},
        },
      ],
      'messages': [
        {'role': 'user', 'content': userPrompt},
      ],
    };

    // Extended thinking requires temperature = 1 (API requirement).
    if (isThinking) {
      bodyMap['thinking'] = {'type': 'enabled', 'budget_tokens': thinkingBudget};
      bodyMap['temperature'] = 1;
    } else {
      bodyMap['temperature'] = temperature;
    }

    final response = await _http
        .post(Uri.parse(_endpoint), headers: headers, body: jsonEncode(bodyMap))
        .timeout(timeout);

    if (response.statusCode != 200) {
      final preview = response.body.length > 300
          ? '${response.body.substring(0, 300)}…'
          : response.body;
      throw Exception('HTTP ${response.statusCode}: $preview');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final content = json['content'] as List?;
    if (content == null || content.isEmpty) {
      final preview = response.body.length > 500
          ? '${response.body.substring(0, 500)}…'
          : response.body;
      throw Exception(
          'Anthropic returned empty content.\n\nRaw response:\n$preview');
    }

    // The response may contain thinking blocks before the text block —
    // extract only the text blocks for the caller.
    final textBlocks = content
        .whereType<Map<String, dynamic>>()
        .where((b) => b['type'] == 'text')
        .toList();
    if (textBlocks.isEmpty) {
      throw Exception('Anthropic response contained no text block.');
    }
    return textBlocks.first['text'] as String;
  }
}
