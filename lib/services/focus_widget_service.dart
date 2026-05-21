import 'dart:convert';

import 'package:home_widget/home_widget.dart';

import '../models/enums.dart';
import 'display_preferences.dart';
import 'focus_list_service.dart';
import 'goal_repository.dart';
import 'goal_service.dart';
import 'hive/hive_goal_repository.dart';

/// Bridges the focus queue to the Android home-screen widget.
///
/// On every focus / goal change [update] serialises the next few pending
/// subtasks — capped by [DisplayPreferences.focusWidgetLayout] — into the
/// `home_widget` shared store and asks the native `FocusWidgetProvider` to
/// redraw. Tapping the widget's check button fires a background broadcast
/// that `home_widget` routes to [focusWidgetBackgroundCallback].
class FocusWidgetService {
  /// Must match the Kotlin class name of the AppWidgetProvider.
  static const String androidProviderName = 'FocusWidgetProvider';

  /// Key under which the JSON payload is stored for the native side.
  static const String payloadKey = 'focus_payload';

  /// URI scheme + host the native check button uses for its broadcast.
  static const String uriScheme = 'todofocus';
  static const String completeHost = 'complete';

  // Live instances reused by the background callback when the app process is
  // still alive — mirrors NotificationService's static-handler pattern.
  static GoalRepository? _repository;
  static FocusListService? _focus;
  static DisplayPreferences? _prefs;

  final GoalRepository _repo;
  final FocusListService _focusList;
  final DisplayPreferences _displayPrefs;

  FocusWidgetService({
    required GoalRepository repository,
    required FocusListService focus,
    required DisplayPreferences prefs,
  })  : _repo = repository,
        _focusList = focus,
        _displayPrefs = prefs {
    _repository = repository;
    _focus = focus;
    _prefs = prefs;
  }

  /// Registers the background interactivity callback. Call once at startup.
  static Future<void> registerBackgroundCallback() async {
    await HomeWidget.registerInteractivityCallback(
      focusWidgetBackgroundCallback,
    );
  }

  /// Re-renders the home-screen widget from the current focus queue.
  Future<void> update() async {
    final payload = buildPayload(
      _displayPrefs.focusWidgetLayout,
      _focusList,
      _repo,
    );
    await HomeWidget.saveWidgetData<String>(payloadKey, payload);
    await HomeWidget.updateWidget(androidName: androidProviderName);
  }

  /// Builds the JSON payload the native widget renders.
  ///
  /// Shape:
  /// ```json
  /// { "layout": "current",
  ///   "rows": [
  ///     {"goalId":"..","subtaskId":"..","goalTitle":"..",
  ///      "goalEmoji":"..","step":"..","isCurrent":true}
  ///   ] }
  /// ```
  static String buildPayload(
    FocusLayout layout,
    FocusListService focus,
    GoalRepository repo,
  ) {
    final maxRows = 1 + layout.extraSteps;
    final rows = <Map<String, dynamic>>[];
    outer:
    for (final group in focus.resolveGroups(repo)) {
      for (final st in group.subtasks) {
        if (st.state != SubTaskState.pending) continue;
        rows.add({
          'goalId': group.goal.goalId,
          'subtaskId': st.subtaskId,
          'goalTitle': group.goal.title,
          'goalEmoji': group.goal.emoji ?? '',
          'step': st.description,
          'isCurrent': rows.isEmpty,
        });
        if (rows.length >= maxRows) break outer;
      }
    }
    return jsonEncode({'layout': layout.name, 'rows': rows});
  }
}

/// Background entry point invoked by `home_widget` when the widget's check
/// button is tapped. Completes the targeted subtask and re-renders the
/// widget. Runs in the main isolate when the app is alive, otherwise in a
/// fresh background isolate (hence the cold-bootstrap fallback).
@pragma('vm:entry-point')
Future<void> focusWidgetBackgroundCallback(Uri? uri) async {
  if (uri == null || uri.host != FocusWidgetService.completeHost) return;
  final goalId = uri.queryParameters['goalId'];
  final subtaskId = uri.queryParameters['subtaskId'];
  if (goalId == null || subtaskId == null) return;

  var repo = FocusWidgetService._repository;
  var focus = FocusWidgetService._focus;
  var prefs = FocusWidgetService._prefs;
  if (repo == null || focus == null || prefs == null) {
    // Cold background isolate — bootstrap a throwaway service stack.
    repo = await HiveGoalRepository.init();
    focus = await FocusListService.init();
    prefs = await DisplayPreferences.init();
  }

  try {
    GoalService(repo, focus).completeSubTask(goalId, subtaskId);
  } catch (_) {
    // Out-of-order completion or a stale id — nothing to do.
  }

  await FocusWidgetService(
    repository: repo,
    focus: focus,
    prefs: prefs,
  ).update();
}
