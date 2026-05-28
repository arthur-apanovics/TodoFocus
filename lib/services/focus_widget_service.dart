import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';

import '../models/enums.dart';
import '../models/sub_task.dart';
import '../screens/widgets/icon_catalog.dart';
import 'display_preferences.dart';
import 'focus_list_service.dart';
import 'goal_repository.dart';
import 'goal_service.dart';
import 'hive/hive_goal_repository.dart';
import 'nudge_service.dart';

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

  /// Optional nudge service. Null in the cold-background-isolate path where
  /// a minimal stack is bootstrapped — nudges are skipped in that case and
  /// will re-appear on the next foreground update.
  final NudgeService? _nudgeService;

  FocusWidgetService({
    required GoalRepository repository,
    required FocusListService focus,
    required DisplayPreferences prefs,
    NudgeService? nudgeService,
  })  : _repo = repository,
        _focusList = focus,
        _displayPrefs = prefs,
        _nudgeService = nudgeService {
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

  /// Prefix for the per-icon SharedPreferences key the native side reads to
  /// resolve a goal's icon-name to a PNG path. e.g. `Goal.emoji == 'rocket'`
  /// → key `goal_icon_rocket` → value is the absolute path to the rendered
  /// PNG. Kept here so both the Dart writer and the Kotlin reader stay in
  /// lock-step.
  static const String iconKeyPrefix = 'goal_icon_';

  /// Re-renders the home-screen widget from the current focus queue.
  Future<void> update() async {
    // Make sure every icon used by a focused goal has been rasterised to PNG
    // before pushing the payload — RemoteViews can't inflate Flutter icons,
    // it can only setImageViewBitmap from a file on disk. Rendering is
    // best-effort: in the background isolate `renderFlutterWidget` may fail
    // because there's no implicit view, and the cache from prior foreground
    // renders is what carries icons through.
    await _ensureIconsRendered();

    // Check and update reword state for idle focused goals before building the
    // payload so the rewrite map is always fresh when the payload is serialised.
    if (_displayPrefs.nudgesEnabled && _nudgeService != null) {
      await _nudgeService.checkAndUpdate(
        _focusList.resolveGroups(_repo),
        heartbeat: _displayPrefs.nudgeHeartbeatDuration,
        promptTemplate: _displayPrefs.rewordPromptTemplate,
      );
    }

    final payload = buildPayload(
      _displayPrefs.focusWidgetLayout,
      _focusList,
      _repo,
      showAllGoals: _displayPrefs.focusWidgetShowAllGoals,
      rewrites: _nudgeService?.rewrites ?? const {},
    );
    await HomeWidget.saveWidgetData<String>(payloadKey, payload);
    await HomeWidget.updateWidget(androidName: androidProviderName);
  }

  /// Returns and clears a pending LLM debug error from the nudge service (set
  /// when a reword generation failed and [LlmSettingsService.debugMode] is on).
  /// Returns null when there is no pending error.
  Future<String?> consumeNudgeDebugError() =>
      _nudgeService?.consumeDebugError() ?? Future.value(null);

  /// Walks the focused goals, collects every distinct icon name they use,
  /// and rasterises each one that isn't already on disk. The PNG path is
  /// saved under [iconKeyPrefix] + name via [HomeWidget.saveWidgetData] so
  /// the Kotlin factory can look it up at render time.
  ///
  /// Cheap on the warm path: the cache hits (`File.existsSync`) skip the
  /// expensive Flutter render pipeline; we only re-rasterise icons we've
  /// never seen before or whose file got cleared.
  Future<void> _ensureIconsRendered() async {
    final iconNames = <String>{};
    for (final group in _focusList.resolveGroups(_repo)) {
      final e = group.goal.emoji;
      if (e != null && e.isNotEmpty) iconNames.add(e);
    }

    for (final name in iconNames) {
      final iconData = iconDataForName(name);
      // Legacy Unicode-emoji strings (no catalog entry) skip rasterisation —
      // the native side renders them inline as text instead.
      if (iconData == null) continue;

      final key = '$iconKeyPrefix$name';
      try {
        final existing = await HomeWidget.getWidgetData<String>(key);
        if (existing != null && existing.isNotEmpty && File(existing).existsSync()) {
          continue;
        }
        await HomeWidget.renderFlutterWidget(
          _WidgetIconCanvas(iconData: iconData),
          key: key,
          logicalSize: const Size(48, 48),
          pixelRatio: 3,
        );
      } catch (_) {
        // Background isolate, missing PlatformDispatcher view, or any other
        // hostile environment — leave the cache as-is and let the native
        // side fall back to the text-prefix path.
      }
    }
  }

  /// Builds the JSON payload the native widget renders.
  ///
  /// Shape:
  /// ```json
  /// { "layout": "current",
  ///   "rows": [
  ///     {"goalId":"..","subtaskId":"..","goalTitle":"..",
  ///      "goalEmoji":"..","step":"..","isCurrent":true,"isFirstInGroup":true,
  ///      "stepColorHex":"#F59E0B"}
  ///   ] }
  /// ```
  ///
  /// [rewrites] is an optional `goalId → SubtaskReword` map produced by
  /// [NudgeService]. When a goal has an entry, the reworded text replaces
  /// [step] on the current row and [stepColorHex] is added so the native side
  /// can colour the step text to signal idle urgency.
  ///
  /// When [showAllGoals] is false (default) the rows are capped globally at
  /// `1 + layout.extraSteps`, so the widget shows at most that many steps from
  /// the single topmost focused goal.
  ///
  /// When [showAllGoals] is true each focused goal contributes its own slice of
  /// up to `1 + layout.extraSteps` rows, so every focused goal is represented
  /// regardless of the total count.
  static String buildPayload(
    FocusLayout layout,
    FocusListService focus,
    GoalRepository repo, {
    bool showAllGoals = false,
    Map<String, SubtaskReword> rewrites = const {},
  }) {
    final maxRowsPerGoal = 1 + layout.extraSteps;
    final rows = <Map<String, dynamic>>[];

    // lastGoalId tracks when we cross a goal boundary so the native side can
    // draw a visual separator between goal groups.
    String? lastGoalId;

    /// Picks the pending subtasks to display for [group], in goal order.
    ///
    /// Strategy:
    ///   1. Focused, still-pending subtasks first (preserve user's intent).
    ///   2. Backfill from the goal's remaining pending subtasks once the
    ///      focused ones are exhausted, until [maxRowsPerGoal] is reached.
    ///
    /// This keeps the widget's row count stable across completions: completing
    /// the topmost focused step doesn't shrink the visible list, because the
    /// next pending step of the same goal slides into the freed slot — exactly
    /// what users expect of a "what's next" surface. Without the backfill the
    /// list would degrade by one row every completion, leaving partially
    /// focused goals with as few as 1-2 visible rows after a few taps.
    List<SubTask> pickPendingForGoal(ResolvedFocusGroup group) {
      final picked = <SubTask>[];
      final added = <String>{};

      // Pass 1: pending subtasks that are explicitly in the focus list.
      for (final st in group.subtasks) {
        if (st.state != SubTaskState.pending) continue;
        if (picked.length >= maxRowsPerGoal) break;
        picked.add(st);
        added.add(st.subtaskId);
      }

      // Pass 2: backfill from the goal's other pending subtasks in sequence
      // order, in case the focus list is empty / has been pruned by completion
      // / never explicitly included every pending step.
      if (picked.length < maxRowsPerGoal) {
        for (final st in group.goal.subtasks) {
          if (st.state != SubTaskState.pending) continue;
          if (added.contains(st.subtaskId)) continue;
          if (picked.length >= maxRowsPerGoal) break;
          picked.add(st);
          added.add(st.subtaskId);
        }
      }
      return picked;
    }

    void addRow(ResolvedFocusGroup group, SubTask st, bool isCurrent) {
      final rewrite = isCurrent ? rewrites[group.goal.goalId] : null;
      final stepText = (rewrite != null && rewrite.subtaskId == st.subtaskId)
          ? rewrite.displayText
          : st.description;
      final row = <String, dynamic>{
        'goalId': group.goal.goalId,
        'subtaskId': st.subtaskId,
        'goalTitle': group.goal.title,
        'goalEmoji': group.goal.emoji ?? '',
        'step': stepText,
        'isCurrent': isCurrent,
        'isFirstInGroup': group.goal.goalId != lastGoalId,
      };
      if (rewrite != null &&
          rewrite.subtaskId == st.subtaskId &&
          rewrite.iteration > 0) {
        final colorHex = SubtaskReword.hexColorForIteration(rewrite.iteration);
        if (colorHex != null) row['stepColorHex'] = colorHex;
      }
      rows.add(row);
      lastGoalId = group.goal.goalId;
    }

    if (showAllGoals) {
      // One slice per goal — each goal contributes up to maxRowsPerGoal rows.
      for (final group in focus.resolveGroups(repo)) {
        final picks = pickPendingForGoal(group);
        for (var i = 0; i < picks.length; i++) {
          addRow(group, picks[i], i == 0);
        }
      }
    } else {
      // Single-goal mode: global cap across all goals.
      outer:
      for (final group in focus.resolveGroups(repo)) {
        for (final st in pickPendingForGoal(group)) {
          addRow(group, st, rows.isEmpty);
          if (rows.length >= maxRowsPerGoal) break outer;
        }
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

  await FocusWidgetService(repository: repo, focus: focus, prefs: prefs)
      .update();
}

/// Minimal off-stage widget rasterised to PNG by [HomeWidget.renderFlutterWidget]
/// for use as a row-divider icon on the home-screen widget.
///
/// Rendered at a single neutral grey so the same PNG is legible on both the
/// light and dark widget backgrounds — the home-screen widget can't follow
/// the app's MediaQuery brightness, so a colour that reads on both is the
/// pragmatic compromise.
class _WidgetIconCanvas extends StatelessWidget {
  final IconData iconData;

  const _WidgetIconCanvas({required this.iconData});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Icon(
        iconData,
        size: 40,
        color: const Color(0xFF8A8A8A),
      ),
    );
  }
}
