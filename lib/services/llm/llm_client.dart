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
  Future<String> complete(String systemPrompt, String userPrompt) async {
    final uri = Uri.parse('${config.baseUrl}/chat/completions');
    final headers = {
      'Content-Type': 'application/json',
      if (config.apiKey?.isNotEmpty == true)
        'Authorization': 'Bearer ${config.apiKey}',
    };
    final body = jsonEncode({
      'model': config.model,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
      'temperature': 0.3,
    });

    final response = await _http
        .post(uri, headers: headers, body: body)
        .timeout(config.timeout);

    if (response.statusCode != 200) {
      throw Exception('LLM request failed: ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return (json['choices'] as List).first['message']['content'] as String;
  }
}
