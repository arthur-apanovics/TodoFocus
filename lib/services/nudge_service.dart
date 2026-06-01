import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import '../models/enums.dart';
import '../models/goal.dart';
import 'focus_list_service.dart';
import 'settings/llm_settings_service.dart';

/// Reword state for a single focused goal's current subtask.
///
/// Iteration advances by one each time the goal sits idle for another
/// heartbeat period (1 = mild reword, 2 = moderate, 3 = urgent). The
/// [displayText] is either the LLM-reworded version or the original
/// subtask description when the LLM was unavailable (in which case only
/// the colour escalation signals urgency).
class SubtaskReword {
  final String subtaskId;
  final String displayText;
  final int iteration; // 1–3

  const SubtaskReword({
    required this.subtaskId,
    required this.displayText,
    required this.iteration,
  });

  /// Hex colour for the Android home-screen widget (no Flutter theme access).
  static String? hexColorForIteration(int iteration) {
    if (iteration <= 0) return null;
    if (iteration == 1) return '#F59E0B'; // amber
    if (iteration == 2) return '#EA580C'; // orange
    return '#E53935'; // red
  }

  /// Theme-aware colour for the in-app Flutter UI.
  static Color? flutterColorForIteration(int iteration, ColorScheme cs) {
    if (iteration <= 0) return null;
    if (iteration == 1) return const Color(0xFFF59E0B); // amber
    if (iteration == 2) return const Color(0xFFEA580C); // orange
    return cs.error; // red — follows the theme
  }
}

/// Manages progressive subtask rewording for idle focused goals.
///
/// When a focused goal has been idle for N heartbeat periods, the current
/// subtask text is reworded by the LLM at escalating urgency levels (1–3).
/// The [rewrites] map is exposed for the in-app Focus screen to read; the
/// same reworded text is also embedded directly in the widget payload so
/// the home-screen widget shows it without separate SharedPreferences keys.
///
/// Reword state resets automatically when the focused subtask changes or
/// the goal resumes activity (any subtask state-change updates
/// [SubTask.lastSeenDate], which is what the idle check reads).
class NudgeService extends ChangeNotifier {
  static const _pendingDebugErrorKey = 'nudge_debug_error';

  final LlmSettingsService _llmSettings;
  final _inFlight = <String>{};
  final _rewrites = <String, SubtaskReword>{};

  NudgeService(this._llmSettings);

  /// Current reword state keyed by goalId. The focus screen and widget
  /// payload both read from this map.
  Map<String, SubtaskReword> get rewrites => Map.unmodifiable(_rewrites);

  /// Scans [groups] and updates reword state for each focused goal.
  ///
  /// - Goals with recent activity (idle < heartbeat) are cleared.
  /// - Goals idle for N × heartbeat get their subtask reworded at urgency N
  ///   (capped at 3). The iteration only advances; it never regresses.
  /// - On LLM failure the iteration still advances so the colour escalates
  ///   even without a text reword.
  ///
  /// Notifies listeners when any entry changes.
  Future<void> checkAndUpdate(
    List<ResolvedFocusGroup> groups, {
    required Duration heartbeat,
    required String promptTemplate,
  }) async {
    final now = DateTime.now();
    var changed = false;

    for (final group in groups) {
      final goal = group.goal;
      final currentSubtask = goal.subtasks
          .where((t) => t.state == SubTaskState.pending)
          .firstOrNull;

      if (currentSubtask == null) {
        if (_rewrites.remove(goal.goalId) != null) changed = true;
        continue;
      }

      final lastActivity = _lastActivityAt(goal);
      final idleSeconds = lastActivity != null
          ? now.difference(lastActivity).inSeconds
          : heartbeat.inSeconds;

      final targetIteration =
          (idleSeconds / heartbeat.inSeconds).floor().clamp(0, 3);

      if (targetIteration == 0) {
        // Goal is active — clear any existing reword.
        if (_rewrites.remove(goal.goalId) != null) changed = true;
        continue;
      }

      final existing = _rewrites[goal.goalId];
      final subtaskChanged = existing?.subtaskId != currentSubtask.subtaskId;

      if (!subtaskChanged &&
          existing != null &&
          existing.iteration >= targetIteration) {
        continue; // already at or ahead of where we need to be
      }

      if (_inFlight.contains(goal.goalId)) continue;

      _inFlight.add(goal.goalId);
      try {
        final client = _llmSettings.buildClient();
        String? reworded;

        if (client != null) {
          try {
            reworded = await client.rewordSubtask(
              currentSubtask.description,
              goalTitle: goal.title,
              goalNotes: goal.notes.isNotEmpty ? goal.notes : null,
              urgencyLevel: targetIteration,
              promptTemplate: promptTemplate,
            );
          } catch (e) {
            if (_llmSettings.debugMode) {
              await HomeWidget.saveWidgetData<String>(
                  _pendingDebugErrorKey, 'Reword LLM error: $e');
            }
          }
        }

        _rewrites[goal.goalId] = SubtaskReword(
          subtaskId: currentSubtask.subtaskId,
          // Fall back to the original text when LLM is unavailable —
          // the colour change still communicates idle urgency.
          displayText: reworded ?? currentSubtask.description,
          iteration: targetIteration,
        );
        changed = true;
      } finally {
        _inFlight.remove(goal.goalId);
      }
    }

    if (changed) notifyListeners();
  }

  /// Returns and clears a pending debug error string (surfaced as a SnackBar
  /// by [AppShell] when [LlmSettingsService.debugMode] is true).
  Future<String?> consumeDebugError() async {
    final error =
        await HomeWidget.getWidgetData<String>(_pendingDebugErrorKey);
    if (error != null && error.isNotEmpty) {
      await HomeWidget.saveWidgetData<String?>(_pendingDebugErrorKey, null);
      return error;
    }
    return null;
  }

  DateTime? _lastActivityAt(Goal goal) {
    DateTime? latest;
    for (final st in goal.subtasks) {
      if (latest == null || st.lastSeenDate.isAfter(latest)) {
        latest = st.lastSeenDate;
      }
    }
    return latest;
  }
}
