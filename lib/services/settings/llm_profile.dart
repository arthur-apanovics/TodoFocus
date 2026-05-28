import 'dart:convert';
import '../llm/anthropic_llm_client.dart';
import '../llm/decomposition_client.dart';
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
        AnthropicProfile.typeKey => AnthropicProfile.fromJson(map),
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

  static const Duration defaultTimeout = Duration(seconds: 60);

  final String endpointUrl;
  final String modelId;
  final String? apiKey;
  final double temperature;
  final Duration timeout;
  final String systemPrompt;
  // For OpenAI reasoning models (o3-mini, o4-mini, etc.).
  // When non-null, temperature is omitted and reasoning_effort is sent instead.
  final String? reasoningEffort; // 'low' | 'medium' | 'high' | null

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
    this.reasoningEffort,
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
    if (reasoningEffort != null) 'reasoningEffort': reasoningEffort,
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
      reasoningEffort: json['reasoningEffort'] as String?,
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
    Object? reasoningEffort = _sentinel,
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
      reasoningEffort: identical(reasoningEffort, _sentinel)
          ? this.reasoningEffort
          : reasoningEffort as String?,
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
        reasoningEffort: reasoningEffort,
      )),
      systemPrompt: systemPrompt,
      easyMin: easyMin,
      easyMax: easyMax,
      hardMin: hardMin,
      hardMax: hardMax,
      impossibleMin: impossibleMin,
      impossibleMax: impossibleMax,
    );
  }
}

// Sentinel for copyWith to distinguish "not provided" from explicit null.
const _sentinel = Object();

// ---------------------------------------------------------------------------
// Anthropic (native Messages API with thinking + prompt caching)
// ---------------------------------------------------------------------------

final class AnthropicProfile extends LlmProfile {
  static const String typeKey = 'anthropic';
  static const Duration defaultTimeout = Duration(seconds: 120);
  static const List<String> knownModels = [
    'claude-opus-4-7',
    'claude-sonnet-4-6',
    'claude-haiku-4-5-20251001',
  ];

  final String apiKey;
  final String modelId;
  final Duration timeout;
  // 0 = thinking disabled. When > 0, the model reasons internally before
  // producing output. Minimum recommended value is 1024.
  final int thinkingBudget;

  // Subtask count bounds — same semantics as OpenAiCompatibleProfile.
  final int easyMin;
  final int easyMax;
  final int hardMin;
  final int hardMax;
  final int impossibleMin;
  final int impossibleMax;

  const AnthropicProfile({
    required this.apiKey,
    required this.modelId,
    this.timeout = defaultTimeout,
    this.thinkingBudget = 0,
    this.easyMin = 3,
    this.easyMax = 6,
    this.hardMin = 10,
    this.hardMax = 20,
    this.impossibleMin = 30,
    this.impossibleMax = 50,
  });

  @override
  String get displayName => 'Anthropic';

  @override
  Map<String, dynamic> toJson() => {
    'type': typeKey,
    'apiKey': apiKey,
    'modelId': modelId,
    if (timeout != defaultTimeout) 'timeoutSeconds': timeout.inSeconds,
    if (thinkingBudget > 0) 'thinkingBudget': thinkingBudget,
    'easyMin': easyMin,
    'easyMax': easyMax,
    'hardMin': hardMin,
    'hardMax': hardMax,
    'impossibleMin': impossibleMin,
    'impossibleMax': impossibleMax,
  };

  factory AnthropicProfile.fromJson(Map<String, dynamic> json) {
    return AnthropicProfile(
      apiKey: json['apiKey'] as String? ?? '',
      modelId: json['modelId'] as String? ?? knownModels[1],
      timeout: json['timeoutSeconds'] != null
          ? Duration(seconds: json['timeoutSeconds'] as int)
          : defaultTimeout,
      thinkingBudget: json['thinkingBudget'] as int? ?? 0,
      easyMin: json['easyMin'] as int? ?? 3,
      easyMax: json['easyMax'] as int? ?? 6,
      hardMin: json['hardMin'] as int? ?? 10,
      hardMax: json['hardMax'] as int? ?? 20,
      impossibleMin: json['impossibleMin'] as int? ?? 30,
      impossibleMax: json['impossibleMax'] as int? ?? 50,
    );
  }

  AnthropicProfile copyWith({
    String? apiKey,
    String? modelId,
    Duration? timeout,
    int? thinkingBudget,
    int? easyMin,
    int? easyMax,
    int? hardMin,
    int? hardMax,
    int? impossibleMin,
    int? impossibleMax,
  }) {
    return AnthropicProfile(
      apiKey: apiKey ?? this.apiKey,
      modelId: modelId ?? this.modelId,
      timeout: timeout ?? this.timeout,
      thinkingBudget: thinkingBudget ?? this.thinkingBudget,
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
      AnthropicLlmClient(
        apiKey: apiKey,
        model: modelId,
        timeout: timeout,
        thinkingBudget: thinkingBudget,
      ),
      easyMin: easyMin,
      easyMax: easyMax,
      hardMin: hardMin,
      hardMax: hardMax,
      impossibleMin: impossibleMin,
      impossibleMax: impossibleMax,
    );
  }
}
