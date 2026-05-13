import 'dart:convert';
import 'package:http/http.dart' as http;
import 'llm_config.dart';

class LlmClient {
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
    final body = jsonEncode({
      'response_format': responseFormat,
      'model': config.model,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
      'temperature': config.temperature,
    });

    final response = await _http
        .post(uri, headers: headers, body: body)
        .timeout(config.timeout);

    if (response.statusCode != 200) {
      final body = response.body.length > 300
          ? '${response.body.substring(0, 300)}…'
          : response.body;
      throw Exception('HTTP ${response.statusCode}: $body');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return (json['choices'] as List).first['message']['content'] as String;
  }
}
