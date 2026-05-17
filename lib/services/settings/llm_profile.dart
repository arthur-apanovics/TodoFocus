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
  static const String defaultSystemPrompt =
      OpenAiDecompositionClient.defaultSystemPrompt;
  static const String defaultBreakdownPrompt =
      OpenAiDecompositionClient.defaultBreakdownPrompt;

  static const Duration defaultTimeout = Duration(seconds: 60);

  final String endpointUrl;
  final String modelId;
  final String? apiKey;
  final double temperature;
  final Duration timeout;
  final String systemPrompt;
  final String breakdownPrompt;

  // Subtask count bounds per difficulty level — configurable in LLM settings.
  final int easyMin;
  final int easyMax;
  final int hardMin;
  final int hardMax;
  final int impossibleMin;
  final int impossibleMax;

  const OpenAiCompatibleProfile({
    required this.endpointUrl,
    required this.modelId,
    this.apiKey,
    this.temperature = 0.3,
    this.timeout = defaultTimeout,
    this.systemPrompt = defaultSystemPrompt,
    this.breakdownPrompt = defaultBreakdownPrompt,
    this.easyMin = 3,
    this.easyMax = 6,
    this.hardMin = 10,
    this.hardMax = 20,
    this.impossibleMin = 30,
    this.impossibleMax = 50,
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
    if (timeout != defaultTimeout) 'timeoutSeconds': timeout.inSeconds,
    if (systemPrompt != defaultSystemPrompt) 'systemPrompt': systemPrompt,
    if (breakdownPrompt != defaultBreakdownPrompt)
      'breakdownPrompt': breakdownPrompt,
    'easyMin': easyMin,
    'easyMax': easyMax,
    'hardMin': hardMin,
    'hardMax': hardMax,
    'impossibleMin': impossibleMin,
    'impossibleMax': impossibleMax,
  };

  factory OpenAiCompatibleProfile.fromJson(Map<String, dynamic> json) {
    return OpenAiCompatibleProfile(
      endpointUrl: json['endpointUrl'] as String? ?? '',
      modelId: json['modelId'] as String? ?? '',
      apiKey: json['apiKey'] as String?,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.3,
      timeout: json['timeoutSeconds'] != null
          ? Duration(seconds: json['timeoutSeconds'] as int)
          : defaultTimeout,
      systemPrompt: json['systemPrompt'] as String? ?? defaultSystemPrompt,
      breakdownPrompt:
          json['breakdownPrompt'] as String? ?? defaultBreakdownPrompt,
      easyMin: json['easyMin'] as int? ?? 3,
      easyMax: json['easyMax'] as int? ?? 6,
      hardMin: json['hardMin'] as int? ?? 10,
      hardMax: json['hardMax'] as int? ?? 20,
      impossibleMin: json['impossibleMin'] as int? ?? 30,
      impossibleMax: json['impossibleMax'] as int? ?? 50,
    );
  }

  OpenAiCompatibleProfile copyWith({
    String? endpointUrl,
    String? modelId,
    String? apiKey,
    double? temperature,
    Duration? timeout,
    String? systemPrompt,
    String? breakdownPrompt,
    int? easyMin,
    int? easyMax,
    int? hardMin,
    int? hardMax,
    int? impossibleMin,
    int? impossibleMax,
  }) {
    return OpenAiCompatibleProfile(
      endpointUrl: endpointUrl ?? this.endpointUrl,
      modelId: modelId ?? this.modelId,
      apiKey: apiKey ?? this.apiKey,
      temperature: temperature ?? this.temperature,
      timeout: timeout ?? this.timeout,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      breakdownPrompt: breakdownPrompt ?? this.breakdownPrompt,
      easyMin: easyMin ?? this.easyMin,
      easyMax: easyMax ?? this.easyMax,
      hardMin: hardMin ?? this.hardMin,
      hardMax: hardMax ?? this.hardMax,
      impossibleMin: impossibleMin ?? this.impossibleMin,
      impossibleMax: impossibleMax ?? this.impossibleMax,
    );
  }

  @override
  DecompositionClient buildClient() {
    return OpenAiDecompositionClient(
      LlmClient(LlmConfig(
        baseUrl: endpointUrl,
        model: modelId,
        apiKey: apiKey,
        temperature: temperature,
        timeout: timeout,
      )),
      systemPrompt: systemPrompt,
      breakdownPrompt: breakdownPrompt,
      easyMin: easyMin,
      easyMax: easyMax,
      hardMin: hardMin,
      hardMax: hardMax,
      impossibleMin: impossibleMin,
      impossibleMax: impossibleMax,
    );
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
