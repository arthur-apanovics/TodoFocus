import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'goal_repository.dart';
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
      'goals': _goals.exportToJson(),
      'settings': _settings.exportToJson(),
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

  // Returns null if the user cancelled. Throws FormatException for invalid JSON.
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

    var imported = 0;
    var skipped = 0;

    final rawGoals = payload['goals'];
    if (rawGoals is List) {
      final result = await _goals.importFromJson(rawGoals);
      imported = result.imported;
      skipped = result.skipped;
    }

    final rawSettings = payload['settings'];
    if (rawSettings is Map<String, dynamic>) {
      await _settings.importFromJson(rawSettings);
    }

    return (imported: imported, skipped: skipped);
  }

  String _dateTag(DateTime dt) =>
      '${dt.year}${_pad(dt.month)}${_pad(dt.day)}';

  String _pad(int n) => n.toString().padLeft(2, '0');
}
