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
  static const _enabledKey = 'llm_enabled';

  final Box<String> _box;
  OpenAiCompatibleProfile _openAiProfile;
  GoblinToolsProfile _goblinProfile;
  String? _activeType; // typeKey of whichever preset is currently active
  bool _enabled;

  LlmSettingsService._({
    required Box<String> box,
    required OpenAiCompatibleProfile openAiProfile,
    required GoblinToolsProfile goblinProfile,
    required String? activeType,
    required bool enabled,
  })  : _box = box,
        _openAiProfile = openAiProfile,
        _goblinProfile = goblinProfile,
        _activeType = activeType,
        _enabled = enabled;

  OpenAiCompatibleProfile get openAiProfile => _openAiProfile;
  GoblinToolsProfile get goblinProfile => _goblinProfile;

  LlmProfile? get activeProfile => switch (_activeType) {
        OpenAiCompatibleProfile.typeKey => _openAiProfile,
        GoblinToolsProfile.typeKey => _goblinProfile,
        _ => null,
      };

  bool get isEnabled => _enabled;

  // Returns a client only when LLM is enabled and a profile is configured.
  DecompositionClient? buildClient() {
    if (!_enabled) return null;
    return activeProfile?.buildClient();
  }

  // Toggles LLM on/off without discarding the stored profiles.
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    await _box.put(_enabledKey, enabled.toString());
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
      enabled: box.get(_enabledKey) == 'true',
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
      service._enabled = true;
      await box.put(_openAiKey, envProfile.encode());
      await box.put(_activeTypeKey, OpenAiCompatibleProfile.typeKey);
      await box.put(_enabledKey, 'true');
    }

    return service;
  }

  static T? _decodeAs<T extends LlmProfile>(String? encoded) {
    final profile = LlmProfile.tryDecode(encoded);
    return profile is T ? profile : null;
  }
}
