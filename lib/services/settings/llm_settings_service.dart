import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../llm/llm_client.dart';
import '../llm/llm_config.dart';
import 'llm_profile.dart';

class LlmSettingsService extends ChangeNotifier {
  static const _boxName = 'app_settings';
  static const _profileKey = 'active_profile';
  static const _enabledKey = 'llm_enabled';

  final Box<String> _box;
  LlmProfile? _profile;
  bool _enabled;

  LlmSettingsService._(this._box)
      : _enabled = _box.get(_enabledKey) == 'true' {
    _profile = LlmProfile.tryDecode(_box.get(_profileKey));
  }

  LlmProfile? get activeProfile => _profile;
  bool get isEnabled => _enabled;

  // Returns a client only when LLM is enabled and a profile is configured.
  LlmClient? buildClient() {
    if (!_enabled) return null;
    final p = _profile;
    return switch (p) {
      OpenAiCompatibleProfile() => p.buildClient(),
      null => null,
    };
  }

  // Toggles LLM on/off without discarding the stored profile.
  void setEnabled(bool enabled) {
    _enabled = enabled;
    _box.put(_enabledKey, enabled.toString());
    notifyListeners();
  }

  // Persists the profile. Never deletes — use setEnabled(false) to disable.
  void setProfile(LlmProfile profile) {
    _profile = profile;
    _box.put(_profileKey, profile.encode());
    notifyListeners();
  }

  static Future<LlmSettingsService> init() async {
    final box = await Hive.openBox<String>(_boxName);
    final service = LlmSettingsService._(box);

    // When --dart-define env vars are present they overwrite stored settings,
    // acting as a build-time configuration shortcut (useful for dev/testing).
    final envConfig = LlmConfig.fromEnvironment();
    if (envConfig != null) {
      final envProfile = OpenAiCompatibleProfile(
        endpointUrl: envConfig.baseUrl,
        modelId: envConfig.model,
        apiKey: envConfig.apiKey,
        temperature: envConfig.temperature,
      );
      service._profile = envProfile;
      service._enabled = true;
      box.put(_profileKey, envProfile.encode());
      box.put(_enabledKey, 'true');
    }

    return service;
  }
}
