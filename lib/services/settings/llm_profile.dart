import 'dart:convert';
import '../llm/decomposition_client.dart';
import '../llm/goblin_tools_client.dart';
import '../llm/llm_client.dart';
import '../llm/llm_config.dart';
import '../llm/openai_decomposition_client.dart';

// Sealed class hierarchy for LLM provider profiles.
// Each subtype serialises itself and builds a DecompositionClient.
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
        GoblinToolsProfile.typeKey => GoblinToolsProfile.fromJson(map),
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }

  DecompositionClient buildClient();
}

// ---------------------------------------------------------------------------
// OpenAI-compatible (llama-server, OpenAI, Together AI, etc.)
// ---------------------------------------------------------------------------

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
  DecompositionClient buildClient() {
    return OpenAiDecompositionClient(LlmClient(LlmConfig(
      baseUrl: endpointUrl,
      model: modelId,
      apiKey: apiKey,
      temperature: temperature,
    )));
  }
}

// ---------------------------------------------------------------------------
// Goblin Tools — https://goblin.tools
// Free, no API key. Spiciness controls subtask count.
// ---------------------------------------------------------------------------

final class GoblinToolsProfile extends LlmProfile {
  static const String typeKey = 'goblin_tools';

  /// 1 = few subtasks, 2 = medium, 3 = many
  final int spiciness;

  const GoblinToolsProfile({this.spiciness = 2});

  @override
  String get displayName => 'Goblin Tools';

  @override
  Map<String, dynamic> toJson() => {
    'type': typeKey,
    'spiciness': spiciness,
  };

  factory GoblinToolsProfile.fromJson(Map<String, dynamic> json) {
    return GoblinToolsProfile(
      spiciness: json['spiciness'] as int? ?? 2,
    );
  }

  GoblinToolsProfile copyWith({int? spiciness}) =>
      GoblinToolsProfile(spiciness: spiciness ?? this.spiciness);

  @override
  DecompositionClient buildClient() =>
      GoblinToolsDecompositionClient(spiciness: spiciness);
}
