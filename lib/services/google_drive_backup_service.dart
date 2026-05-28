import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:hive_flutter/hive_flutter.dart';

import 'focus_list_service.dart';
import 'goal_repository.dart';
import 'settings/llm_settings_service.dart';

/// Backs up all app data (goals + LLM settings + focus list) to the user's
/// Google Drive appDataFolder — a private folder only this app can access.
///
/// The backup format is identical to [BackupService] v2 so exported local
/// files and Drive backups are cross-compatible.
///
/// ### Android setup required
/// Before sign-in will work you must register the app in Google Cloud Console:
///   1. Create (or reuse) a project and enable the Google Drive API.
///   2. Add an Android OAuth 2.0 credential with:
///        • Package name: com.example.todo_app
///        • SHA-1 certificate fingerprint of your debug/release keystore.
/// No `google-services.json` file is required.
class GoogleDriveBackupService extends ChangeNotifier {
  static const _backupFileName = 'todofocus_backup.json';
  static const _lastBackupTsKey = 'gdrive_backup_last_ts';
  static const _autoBackupThreshold = Duration(hours: 1);
  static const _scopes = [drive.DriveApi.driveAppdataScope];
  static const _backupVersion = 2;

  final GoalRepository _goals;
  final LlmSettingsService _settings;
  final FocusListService _focus;
  final GoogleSignIn _googleSignIn;
  final Box<String> _box;

  GoogleSignInAccount? _currentUser;
  bool _isBusy = false;
  String? _lastError;
  DateTime? _lastBackupAt;

  GoogleDriveBackupService._({
    required GoalRepository goals,
    required LlmSettingsService settings,
    required FocusListService focus,
    required GoogleSignIn googleSignIn,
    required Box<String> box,
    required GoogleSignInAccount? currentUser,
    required DateTime? lastBackupAt,
  })  : _goals = goals,
        _settings = settings,
        _focus = focus,
        _googleSignIn = googleSignIn,
        _box = box,
        _currentUser = currentUser,
        _lastBackupAt = lastBackupAt;

  GoogleSignInAccount? get currentUser => _currentUser;
  bool get isSignedIn => _currentUser != null;
  bool get isBusy => _isBusy;

  /// Non-null only after a failed operation — cleared on next success.
  String? get lastError => _lastError;

  /// Time of last successful backup, or null if never backed up.
  DateTime? get lastBackupAt => _lastBackupAt;

  static Future<GoogleDriveBackupService> init({
    required GoalRepository goals,
    required LlmSettingsService settings,
    required FocusListService focus,
  }) async {
    // Hive deduplicates open boxes by name — safe to open here even if another
    // service already has the same box open.
    final box = await Hive.openBox<String>('app_settings');
    final ts = box.get(_lastBackupTsKey);
    final lastBackupAt = ts != null ? DateTime.tryParse(ts) : null;

    final googleSignIn = GoogleSignIn(scopes: _scopes);
    GoogleSignInAccount? currentUser;
    try {
      // Restores the previous session without showing any UI. Returns null if
      // the user has never signed in or revoked access.
      currentUser = await googleSignIn.signInSilently();
    } catch (_) {
      // Silent failure is normal on first launch or after permission revocation.
    }

    return GoogleDriveBackupService._(
      goals: goals,
      settings: settings,
      focus: focus,
      googleSignIn: googleSignIn,
      box: box,
      currentUser: currentUser,
      lastBackupAt: lastBackupAt,
    );
  }

  // ---------------------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------------------

  /// Shows the Google account picker. Returns true if the user signed in.
  Future<bool> signIn() async {
    _setBusy(true);
    try {
      _currentUser = await _googleSignIn.signIn();
      _lastError = null;
      return _currentUser != null;
    } catch (e) {
      _lastError = _friendlyError(e);
      return false;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentUser = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Backup
  // ---------------------------------------------------------------------------

  /// Uploads goals, LLM settings, and focus list to the Drive appDataFolder.
  /// Creates the backup file on first call; updates it on subsequent calls.
  /// Returns true on success.
  Future<bool> backup() async {
    if (!isSignedIn) return false;
    _setBusy(true);
    try {
      final driveApi = await _driveApi();
      if (driveApi == null) return false;

      final payload = {
        'version': _backupVersion,
        'exportedAt': DateTime.now().toIso8601String(),
        'goals': _goals.exportToJson(),
        'settings': _settings.exportToJson(),
        'focus': _focus.exportToJson(),
      };
      final bytes = utf8.encode(jsonEncode(payload));
      final media = drive.Media(
        Stream.value(bytes),
        bytes.length,
        contentType: 'application/json; charset=utf-8',
      );

      final existingId = await _findBackupFileId(driveApi);
      if (existingId != null) {
        await driveApi.files.update(drive.File(), existingId, uploadMedia: media);
      } else {
        await driveApi.files.create(
          drive.File()
            ..name = _backupFileName
            ..parents = ['appDataFolder'],
          uploadMedia: media,
        );
      }

      _lastBackupAt = DateTime.now();
      await _box.put(_lastBackupTsKey, _lastBackupAt!.toIso8601String());
      _lastError = null;
      return true;
    } catch (e) {
      _lastError = _friendlyError(e);
      return false;
    } finally {
      _setBusy(false);
    }
  }

  // ---------------------------------------------------------------------------
  // Restore
  // ---------------------------------------------------------------------------

  /// Downloads the backup from Drive and applies it locally, replacing all
  /// current goals, LLM settings, and the focus list.
  ///
  /// Returns `(ok: true, imported: N, skipped: M)` on success.
  Future<({bool ok, int imported, int skipped})> restore() async {
    if (!isSignedIn) return (ok: false, imported: 0, skipped: 0);
    _setBusy(true);
    try {
      final driveApi = await _driveApi();
      if (driveApi == null) return (ok: false, imported: 0, skipped: 0);

      final fileId = await _findBackupFileId(driveApi);
      if (fileId == null) {
        _lastError = 'No backup found in Google Drive.';
        return (ok: false, imported: 0, skipped: 0);
      }

      final media = await driveApi.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final bytes = await media.stream.expand((chunk) => chunk).toList();
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

      var imported = 0;
      var skipped = 0;

      final rawGoals = json['goals'];
      if (rawGoals is List) {
        final result = await _goals.importFromJson(rawGoals);
        imported = result.imported;
        skipped = result.skipped;
      }

      final rawSettings = json['settings'];
      if (rawSettings is Map<String, dynamic>) {
        await _settings.importFromJson(rawSettings);
      }

      // Import focus last so it sees the freshly restored goals. Old entries
      // pointing at missing IDs become dangling refs dropped at resolve time.
      final rawFocus = json['focus'];
      if (rawFocus is List) {
        await _focus.importFromJson(rawFocus);
      } else {
        await _focus.clearAll();
      }

      _lastError = null;
      return (ok: true, imported: imported, skipped: skipped);
    } catch (e) {
      _lastError = _friendlyError(e);
      return (ok: false, imported: 0, skipped: 0);
    } finally {
      _setBusy(false);
    }
  }

  // ---------------------------------------------------------------------------
  // Auto-backup
  // ---------------------------------------------------------------------------

  /// Backs up silently if signed in and the last backup is older than
  /// [_autoBackupThreshold]. Safe to call on every app resume.
  Future<void> autoBackupIfStale() async {
    if (!isSignedIn) return;
    final now = DateTime.now();
    if (_lastBackupAt != null &&
        now.difference(_lastBackupAt!) < _autoBackupThreshold) return;
    await backup();
  }

  // ---------------------------------------------------------------------------
  // Drive helpers
  // ---------------------------------------------------------------------------

  Future<drive.DriveApi?> _driveApi() async {
    try {
      final client = await _googleSignIn.authenticatedClient();
      return client != null ? drive.DriveApi(client) : null;
    } catch (_) {
      // Token refresh failed — treat as signed out.
      _currentUser = null;
      notifyListeners();
      return null;
    }
  }

  Future<String?> _findBackupFileId(drive.DriveApi api) async {
    final result = await api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$_backupFileName'",
      $fields: 'files(id)',
    );
    return result.files?.firstOrNull?.id;
  }

  static String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('network_error') || s.contains('SocketException')) {
      return 'Network error — check your connection and try again.';
    }
    if (s.contains('access_denied') || s.contains('sign_in_canceled')) {
      return 'Sign-in was cancelled or access was denied.';
    }
    return s;
  }

  void _setBusy(bool v) {
    _isBusy = v;
    notifyListeners();
  }
}
