import 'dart:convert';
import '../llm/llm_client.dart';
import '../llm/llm_config.dart';

// Sealed class hierarchy for LLM provider profiles.
// Each subtype knows how to serialize itself and build an LlmClient.
// Add new subtypes here as new provider integrations are needed.
sealed class LlmProfile {
  const LlmProfile();

  String get displayName;
  Map<String, dynamic> toJson();

  String encode() => jsonEncode(toJson());

  static LlmProfile? tryDecode(String? encoded) {
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final map = jsonDecode(encoded) as Map<String, dynamic>;
      return switch (map['type'] as String?) {
        OpenAiCompatibleProfile.typeKey => OpenAiCompatibleProfile.fromJson(map),
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }

  LlmClient buildClient();
}

final class OpenAiCompatibleProfile extends LlmProfile {
  static const String typeKey = 'openai_compatible';

  final String endpointUrl;
  final String modelId;
  final String? apiKey;
  final double temperature;

  const OpenAiCompatibleProfile({
    required this.endpointUrl,
    required this.modelId,
    this.apiKey,
    this.temperature = 0.3,
  });

  @override
  String get displayName => 'OpenAI Compatible';

  @override
  Map<String, dynamic> toJson() => {
    'type': typeKey,
    'endpointUrl': endpointUrl,
    'modelId': modelId,
    if (apiKey?.isNotEmpty == true) 'apiKey': apiKey,
    'temperature': temperature,
  };

  factory OpenAiCompatibleProfile.fromJson(Map<String, dynamic> json) {
    return OpenAiCompatibleProfile(
      endpointUrl: json['endpointUrl'] as String? ?? '',
      modelId: json['modelId'] as String? ?? '',
      apiKey: json['apiKey'] as String?,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.3,
    );
  }

  OpenAiCompatibleProfile copyWith({
    String? endpointUrl,
    String? modelId,
    String? apiKey,
    double? temperature,
  }) {
    return OpenAiCompatibleProfile(
      endpointUrl: endpointUrl ?? this.endpointUrl,
      modelId: modelId ?? this.modelId,
      apiKey: apiKey ?? this.apiKey,
      temperature: temperature ?? this.temperature,
    );
  }

  @override
  LlmClient buildClient() {
    return LlmClient(LlmConfig(
      baseUrl: endpointUrl,
      model: modelId,
      apiKey: apiKey,
      temperature: temperature,
    ));
  }
}
