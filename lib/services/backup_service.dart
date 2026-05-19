import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'focus_list_service.dart';
import 'goal_repository.dart';
import 'settings/llm_settings_service.dart';

typedef BackupResult = ({int imported, int skipped});

class BackupService {
  // Bumped from 1 → 2 when the focus list moved into FocusListService and
  // out of the goal model. Version is a hint for tooling — the importer
  // accepts any version and ignores fields it doesn't recognise.
  static const int _version = 2;

  final GoalRepository _goals;
  final LlmSettingsService _settings;
  final FocusListService _focus;

  BackupService({
    required GoalRepository goals,
    required LlmSettingsService settings,
    required FocusListService focus,
  })  : _goals = goals,
        _settings = settings,
        _focus = focus;

  // Opens the system save-file picker so the user chooses the destination.
  // Returns true if the file was saved, false if the user cancelled.
  Future<bool> export() async {
    final now = DateTime.now();
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode({
      'version': _version,
      'exportedAt': now.toIso8601String(),
      'goals': _goals.exportToJson(),
      'settings': _settings.exportToJson(),
      'focus': _focus.exportToJson(),
    })));

    final path = await FilePicker.platform.saveFile(
      fileName: 'todofocus_${_dateTag(now)}.json',
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    return path != null;
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

    // Focus list is imported last so it sees the freshly-restored goals.
    // Entries pointing at goal/subtask IDs that didn't survive the import
    // become dangling refs and are dropped silently at resolve time.
    final rawFocus = payload['focus'];
    if (rawFocus is List) {
      await _focus.importFromJson(rawFocus);
    } else {
      // No focus block (older backup) → clear any stale entries so the
      // restored repo doesn't carry over yesterday's working set.
      await _focus.clearAll();
    }

    return (imported: imported, skipped: skipped);
  }

  String _dateTag(DateTime dt) =>
      '${dt.year}${_pad(dt.month)}${_pad(dt.day)}';

  String _pad(int n) => n.toString().padLeft(2, '0');
}
