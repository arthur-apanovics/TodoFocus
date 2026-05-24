import 'package:home_widget/home_widget.dart';

import '../models/goal.dart';
import '../models/enums.dart';
import 'focus_list_service.dart';
import 'settings/llm_settings_service.dart';

/// Manages inactivity nudge messages for the home-screen widget.
///
/// When a focused goal has not had any subtask state-change within the
/// configured [heartbeat], [checkAndGetNudges] generates a short LLM nudge
/// and caches it in [HomeWidget]'s SharedPreferences (so the native widget
/// can read it without the app being foreground). Cached nudges are
/// auto-refreshed once they are older than 2 × heartbeat so a long-idle goal
/// doesn't show the same line forever.
///
/// Nudges are cleared automatically whenever [checkAndGetNudges] sees that a
/// goal's last-activity timestamp is within the heartbeat window — i.e., the
/// user just did something with the goal, so the nudge is no longer needed.
class NudgeService {
  static const _msgPrefix = 'nudge_msg_';
  static const _tsPrefix = 'nudge_ts_';
  static const _pendingDebugErrorKey = 'nudge_debug_error';

  /// Shown on the widget when nudges are enabled but the LLM call fails.
  static const _fallbackNudge =
      '⏰ This one has been waiting — one small step is all it takes.';

  final LlmSettingsService _llmSettings;

  /// Per-goal guard: prevents duplicate in-flight LLM calls when update()
  /// fires in rapid succession (both repository + focus listeners).
  final _inFlight = <String>{};

  NudgeService(this._llmSettings);

  /// Scans [groups] and returns a `goalId → nudge text` map.
  ///
  /// Goals with recent activity get their cached nudge cleared; stale goals
  /// get a freshly generated (or cached) nudge. The returned map only contains
  /// goals that should currently display a nudge.
  Future<Map<String, String>> checkAndGetNudges(
    List<ResolvedFocusGroup> groups, {
    required Duration heartbeat,
    required String promptTemplate,
  }) async {
    final result = <String, String>{};
    final now = DateTime.now();

    for (final group in groups) {
      final goal = group.goal;
      final currentSubtask = goal.subtasks
          .where((t) => t.state == SubTaskState.pending)
          .firstOrNull;

      if (currentSubtask == null) {
        await _clearNudge(goal.goalId);
        continue;
      }

      final lastActivity = _lastActivityAt(goal);
      final isStale = lastActivity == null ||
          now.difference(lastActivity) >= heartbeat;

      if (!isStale) {
        await _clearNudge(goal.goalId);
        continue;
      }

      final existingMsg = await _getMsg(goal.goalId);
      final existingTs = await _getTs(goal.goalId);
      final needsRefresh = existingMsg == null ||
          (existingTs != null &&
              now.difference(existingTs) >= heartbeat * 2);

      if (!needsRefresh && existingMsg != null) {
        result[goal.goalId] = existingMsg;
        continue;
      }

      if (_inFlight.contains(goal.goalId)) {
        if (existingMsg != null) result[goal.goalId] = existingMsg;
        continue;
      }

      _inFlight.add(goal.goalId);
      try {
        final client = _llmSettings.buildClient();
        final staleDuration =
            lastActivity != null ? now.difference(lastActivity) : heartbeat;

        final nextSubtask = goal.subtasks
            .where((t) => t.state == SubTaskState.pending)
            .skip(1)
            .firstOrNull;

        String? msg;
        String? errorForDebug;
        if (client != null) {
          try {
            msg = await client.generateNudge(
              goal.title,
              goalDescription: goal.description,
              currentSubtask: currentSubtask.description,
              nextSubtask: nextSubtask?.description,
              staleDuration: staleDuration,
              promptTemplate: promptTemplate,
            );
          } catch (e) {
            errorForDebug = e.toString();
          }
        }

        if (errorForDebug != null && _llmSettings.debugMode) {
          await HomeWidget.saveWidgetData<String>(
              _pendingDebugErrorKey, 'Nudge LLM error: $errorForDebug');
        }

        final nudge =
            msg?.trim().isNotEmpty == true ? msg! : _fallbackNudge;
        await _saveNudge(goal.goalId, nudge);
        result[goal.goalId] = nudge;
      } finally {
        _inFlight.remove(goal.goalId);
      }
    }

    return result;
  }

  /// Returns and clears a pending debug error string (shown as a SnackBar by
  /// [AppShell] when [LlmSettingsService.debugMode] is true). Returns null
  /// when there is no pending error.
  Future<String?> consumeDebugError() async {
    final error =
        await HomeWidget.getWidgetData<String>(_pendingDebugErrorKey);
    if (error != null && error.isNotEmpty) {
      await HomeWidget.saveWidgetData<String?>(_pendingDebugErrorKey, null);
      return error;
    }
    return null;
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  /// Derives goal-level activity as the most recent [SubTask.lastSeenDate]
  /// across all of the goal's subtasks. Returns null when the goal has no
  /// subtasks at all.
  DateTime? _lastActivityAt(Goal goal) {
    DateTime? latest;
    for (final st in goal.subtasks) {
      if (latest == null || st.lastSeenDate.isAfter(latest)) {
        latest = st.lastSeenDate;
      }
    }
    return latest;
  }

  Future<void> _saveNudge(String goalId, String msg) async {
    await HomeWidget.saveWidgetData<String>('$_msgPrefix$goalId', msg);
    await HomeWidget.saveWidgetData<String>(
        '$_tsPrefix$goalId', DateTime.now().toIso8601String());
  }

  Future<void> _clearNudge(String goalId) async {
    await HomeWidget.saveWidgetData<String>('$_msgPrefix$goalId', '');
    await HomeWidget.saveWidgetData<String>('$_tsPrefix$goalId', '');
  }

  Future<String?> _getMsg(String goalId) async {
    final s =
        await HomeWidget.getWidgetData<String>('$_msgPrefix$goalId');
    return (s == null || s.isEmpty) ? null : s;
  }

  Future<DateTime?> _getTs(String goalId) async {
    final s =
        await HomeWidget.getWidgetData<String>('$_tsPrefix$goalId');
    return (s == null || s.isEmpty) ? null : DateTime.tryParse(s);
  }
}
