import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../llm/decomposition_client.dart';
import '../llm/llm_config.dart';
import 'llm_profile.dart';

// Each profile type is stored under its own key so switching active preset
// never overwrites the other type's saved configuration.
class LlmSettingsService extends ChangeNotifier {
  static const _boxName = 'app_settings';
  static const _openAiKey = 'openai_profile';
  static const _goblinKey = 'goblin_profile';
  static const _activeTypeKey = 'active_profile_type';
  static const _debugModeKey = 'llm_debug_mode';
  static const _generateEmojisKey = 'llm_generate_emojis';

  final Box<String> _box;
  OpenAiCompatibleProfile _openAiProfile;
  GoblinToolsProfile _goblinProfile;
  String? _activeType; // typeKey of whichever preset is currently active
  bool _debugMode;
  bool _generateEmojis;

  LlmSettingsService._({
    required Box<String> box,
    required OpenAiCompatibleProfile openAiProfile,
    required GoblinToolsProfile goblinProfile,
    required String? activeType,
    required bool debugMode,
    required bool generateEmojis,
  })  : _box = box,
        _openAiProfile = openAiProfile,
        _goblinProfile = goblinProfile,
        _activeType = activeType,
        _debugMode = debugMode,
        _generateEmojis = generateEmojis;

  OpenAiCompatibleProfile get openAiProfile => _openAiProfile;
  GoblinToolsProfile get goblinProfile => _goblinProfile;

  LlmProfile? get activeProfile => switch (_activeType) {
        OpenAiCompatibleProfile.typeKey => _openAiProfile,
        GoblinToolsProfile.typeKey => _goblinProfile,
        _ => null,
      };

  bool get debugMode => _debugMode;
  bool get generateEmojis => _generateEmojis;

  // Returns a client when a profile is configured, null otherwise.
  // The app always operates in LLM mode; keyword fallback handles failures.
  DecompositionClient? buildClient() => activeProfile?.buildClient();

  Future<void> setGenerateEmojis(bool value) async {
    _generateEmojis = value;
    await _box.put(_generateEmojisKey, value.toString());
    notifyListeners();
  }

  Future<void> setDebugMode(bool value) async {
    _debugMode = value;
    await _box.put(_debugModeKey, value.toString());
    notifyListeners();
  }

  // Saves the profile under its own type key and updates the active type.
  // Saving OpenAI settings never touches the stored Goblin config, and vice versa.
  Future<void> setProfile(LlmProfile profile) async {
    switch (profile) {
      case OpenAiCompatibleProfile():
        _openAiProfile = profile;
        _activeType = OpenAiCompatibleProfile.typeKey;
        await _box.put(_openAiKey, profile.encode());
      case GoblinToolsProfile():
        _goblinProfile = profile;
        _activeType = GoblinToolsProfile.typeKey;
        await _box.put(_goblinKey, profile.encode());
    }
    await _box.put(_activeTypeKey, _activeType!);
    notifyListeners();
  }

  Map<String, dynamic> exportToJson() => {
        'generateEmojis': _generateEmojis,
        'activeProfileType': switch (activeProfile) {
          OpenAiCompatibleProfile() => OpenAiCompatibleProfile.typeKey,
          GoblinToolsProfile() => GoblinToolsProfile.typeKey,
          null => null,
        },
        'openaiProfile': _openAiProfile.toJson(),
        'goblinProfile': _goblinProfile.toJson(),
      };

  // Restores settings from a backup snapshot. Each field is applied
  // independently; invalid or missing values fall back to the current value.
  Future<void> importFromJson(Map<String, dynamic> json) async {
    final activeType = json['activeProfileType'] as String?;
    final generateEmojis = json['generateEmojis'];

    OpenAiCompatibleProfile? openAi;
    try {
      final raw = json['openaiProfile'];
      if (raw is Map<String, dynamic>) {
        openAi = OpenAiCompatibleProfile.fromJson(raw);
      }
    } catch (_) {}

    GoblinToolsProfile? goblin;
    try {
      final raw = json['goblinProfile'];
      if (raw is Map<String, dynamic>) {
        goblin = GoblinToolsProfile.fromJson(raw);
      }
    } catch (_) {}

    _openAiProfile = openAi ?? _openAiProfile;
    _goblinProfile = goblin ?? _goblinProfile;
    _activeType = activeType;
    _generateEmojis =
        generateEmojis is bool ? generateEmojis : _generateEmojis;
    await _box.put(_openAiKey, _openAiProfile.encode());
    await _box.put(_goblinKey, _goblinProfile.encode());
    if (activeType != null) {
      await _box.put(_activeTypeKey, activeType);
    } else {
      await _box.delete(_activeTypeKey);
    }
    await _box.put(_generateEmojisKey, _generateEmojis.toString());
    notifyListeners();
  }

  static Future<LlmSettingsService> init() async {
    final box = await Hive.openBox<String>(_boxName);

    // --- One-time migration from old single-key format ---
    final legacy = box.get('active_profile');
    if (legacy != null &&
        box.get(_openAiKey) == null &&
        box.get(_goblinKey) == null) {
      final old = LlmProfile.tryDecode(legacy);
      if (old is OpenAiCompatibleProfile) {
        await box.put(_openAiKey, old.encode());
        await box.put(_activeTypeKey, OpenAiCompatibleProfile.typeKey);
      } else if (old is GoblinToolsProfile) {
        await box.put(_goblinKey, old.encode());
        await box.put(_activeTypeKey, GoblinToolsProfile.typeKey);
      }
    }

    final openAiProfile = _decodeAs<OpenAiCompatibleProfile>(
          box.get(_openAiKey),
        ) ??
        const OpenAiCompatibleProfile(endpointUrl: '', modelId: '');

    final goblinProfile =
        _decodeAs<GoblinToolsProfile>(box.get(_goblinKey)) ??
            const GoblinToolsProfile();

    final service = LlmSettingsService._(
      box: box,
      openAiProfile: openAiProfile,
      goblinProfile: goblinProfile,
      activeType: box.get(_activeTypeKey),
      debugMode: box.get(_debugModeKey) == 'true',
      generateEmojis: box.get(_generateEmojisKey) == 'true',
    );

    // --dart-define env vars overwrite stored OpenAI settings on launch.
    final envConfig = LlmConfig.fromEnvironment();
    if (envConfig != null) {
      final envProfile = OpenAiCompatibleProfile(
        endpointUrl: envConfig.baseUrl,
        modelId: envConfig.model,
        apiKey: envConfig.apiKey,
        temperature: envConfig.temperature,
      );
      service._openAiProfile = envProfile;
      service._activeType = OpenAiCompatibleProfile.typeKey;
      await box.put(_openAiKey, envProfile.encode());
      await box.put(_activeTypeKey, OpenAiCompatibleProfile.typeKey);
    }

    return service;
  }

  static T? _decodeAs<T extends LlmProfile>(String? encoded) {
    final profile = LlmProfile.tryDecode(encoded);
    return profile is T ? profile : null;
  }
}
