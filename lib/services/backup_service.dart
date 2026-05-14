import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/goal.dart';
import 'goal_repository.dart';
import 'settings/llm_profile.dart';
import 'settings/llm_settings_service.dart';

typedef BackupResult = ({int imported, int skipped});

class BackupService {
  static const int _version = 1;

  final GoalRepository _goals;
  final LlmSettingsService _settings;

  BackupService({
    required GoalRepository goals,
    required LlmSettingsService settings,
  })  : _goals = goals,
        _settings = settings;

  Future<void> export() async {
    final now = DateTime.now();
    final payload = jsonEncode({
      'version': _version,
      'exportedAt': now.toIso8601String(),
      'goals': _goals.all.map((g) => g.toJson()).toList(),
      'settings': {
        'llmEnabled': _settings.isEnabled,
        'activeProfileType': switch (_settings.activeProfile) {
          OpenAiCompatibleProfile() => OpenAiCompatibleProfile.typeKey,
          GoblinToolsProfile() => GoblinToolsProfile.typeKey,
          null => null,
        },
        'openaiProfile': _settings.openAiProfile.toJson(),
        'goblinProfile': _settings.goblinProfile.toJson(),
      },
    });

    final dir = await getTemporaryDirectory();
    final tag = _dateTag(now);
    final file = File('${dir.path}/todofocus_$tag.json');
    await file.writeAsString(payload);

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/json')],
      subject: 'TodoFocus backup $tag',
    );
  }

  // Returns null if the user cancelled the file picker.
  // Throws FormatException if the selected file is not valid JSON.
  Future<BackupResult?> import() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return null;

    final bytes = picked.files.first.bytes;
    if (bytes == null) return null;

    final Map<String, dynamic> payload;
    try {
      payload = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      throw const FormatException('The selected file is not valid JSON');
    }

    int imported = 0;
    int skipped = 0;

    // Replace all goals. Each entry is parsed independently so a single
    // malformed goal doesn't abort the whole restore.
    final rawGoals = payload['goals'];
    if (rawGoals is List) {
      await _goals.clear();
      for (final item in rawGoals) {
        try {
          _goals.save(Goal.fromJson(item as Map<String, dynamic>));
          imported++;
        } catch (_) {
          skipped++;
        }
      }
    }

    // Restore settings field-by-field; invalid entries fall back to whatever
    // is currently stored.
    final rawSettings = payload['settings'];
    if (rawSettings is Map<String, dynamic>) {
      await _restoreSettings(rawSettings);
    }

    return (imported: imported, skipped: skipped);
  }

  Future<void> _restoreSettings(Map<String, dynamic> json) async {
    final enabled = json['llmEnabled'];
    final activeType = json['activeProfileType'] as String?;

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

    await _settings.restoreFromBackup(
      enabled: enabled is bool ? enabled : _settings.isEnabled,
      activeType: activeType,
      openAiProfile: openAi ?? _settings.openAiProfile,
      goblinProfile: goblin ?? _settings.goblinProfile,
    );
  }

  String _dateTag(DateTime dt) =>
      '${dt.year}${_pad(dt.month)}${_pad(dt.day)}';

  String _pad(int n) => n.toString().padLeft(2, '0');
}
