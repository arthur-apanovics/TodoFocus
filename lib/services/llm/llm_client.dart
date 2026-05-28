import 'dart:convert';
import 'package:http/http.dart' as http;
import 'llm_config.dart';

/// Minimal interface shared by all low-level LLM HTTP clients.
/// [OpenAiDecompositionClient] depends on this so it works with both
/// OpenAI-compatible and Anthropic backends.
abstract interface class LlmCompletionClient {
  Future<String> complete(
    String systemPrompt,
    String userPrompt, {
    Map<String, dynamic>? responseSchema,
  });
}

class LlmClient implements LlmCompletionClient {
  final LlmConfig config;
  final http.Client _http;

  LlmClient(this.config, {http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  // Sends a single chat completion and returns the assistant message content.
  // Throws on non-200 status, timeout, or network error — callers handle fallback.
  //
  // [responseSchema] is a JSON Schema object. When provided, llama-server
  // compiles it to a GBNF grammar and constrains the sampler — the model
  // cannot produce output that violates the schema. Falls back to plain
  // json_object mode when omitted (e.g. for backends that don't support it).
  @override
  Future<String> complete(
    String systemPrompt,
    String userPrompt, {
    Map<String, dynamic>? responseSchema,
  }) async {
    final uri = Uri.parse('${config.baseUrl}/chat/completions');
    final isOpenRouter = uri.host.contains('openrouter.ai');
    final headers = {
      'Content-Type': 'application/json',
      if (config.apiKey?.isNotEmpty == true)
        'Authorization': 'Bearer ${config.apiKey}',
      // OpenRouter uses these for rate-limit tiers and model rankings.
      if (isOpenRouter) 'HTTP-Referer': 'https://github.com/arthur-apanovics/todofocus',
      if (isOpenRouter) 'X-Title': 'TodoFocus',
    };
    final responseFormat = responseSchema != null
        ? {
            'type': 'json_schema',
            'json_schema': {
              'name': 'response',
              'strict': true,
              'schema': responseSchema,
            },
          }
        : {'type': 'json_object'};

    // Reasoning models (o3-mini, o4-mini, etc.) require reasoning_effort
    // instead of temperature, which must be omitted entirely when set.
    final Map<String, dynamic> body;
    if (config.reasoningEffort != null) {
      body = {
        'response_format': responseFormat,
        'model': config.model,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
        'reasoning_effort': config.reasoningEffort,
      };
    } else {
      body = {
        'response_format': responseFormat,
        'model': config.model,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
        'temperature': config.temperature,
      };
    }

    final response = await _http
        .post(uri, headers: headers, body: jsonEncode(body))
        .timeout(config.timeout);

    if (response.statusCode != 200) {
      final b = response.body.length > 300
          ? '${response.body.substring(0, 300)}…'
          : response.body;
      throw Exception('HTTP ${response.statusCode}: $b');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = json['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      final preview = response.body.length > 500
          ? '${response.body.substring(0, 500)}…'
          : response.body;
      throw Exception('LLM returned no choices.\n\nRaw response:\n$preview');
    }
    final content = (choices.first as Map<String, dynamic>)['message']
        ?['content'];
    if (content == null) {
      final preview = response.body.length > 500
          ? '${response.body.substring(0, 500)}…'
          : response.body;
      throw Exception(
          'LLM returned null content (model may not support JSON schema).'
          '\n\nRaw response:\n$preview');
    }
    return content as String;
  }
}
