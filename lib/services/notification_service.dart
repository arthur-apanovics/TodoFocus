import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import '../models/enums.dart';
import '../theme/app_colors.dart';
import 'focus_list_service.dart';
import 'goal_repository.dart';
import 'goal_service.dart';
import 'hive/hive_goal_repository.dart';

/// Owns the single persistent "focus" notification.
///
/// Design intent: this notification is a **passive, silent** reminder that
/// sits in the shade so the user can glance at what to work on next — it must
/// never buzz, sound, or pop up as a heads-up. That is why the channel is
/// [NotificationImportance.Low]. Content updates (a new current subtask, a
/// finished goal) silently refresh the same notification rather than alerting.
///
/// There is exactly one notification slot ([_notifId]). It has two states:
///   • **focus** — focus list has pending work: a rich, expandable step list.
///   • **empty** — nothing assigned: a "plan your day" nudge, shown only when
///     the user has the plan-your-day reminder enabled.
class NotificationService {
  static const String markDoneActionKey = 'mark_done';
  static const String breakdownActionKey = 'breakdown';
  static const int _notifId = 1;
  static const String _channelKey = 'focus_v2';

  // Legacy identifiers cleaned up on init: the old High-importance focus
  // channel and the standalone scheduled morning-prompt notification, which
  // is now folded into this notification's empty state.
  static const String _legacyChannelKey = 'focus_task';
  static const String _legacyMorningChannelKey = 'morning_prompt';
  static const int _legacyMorningPromptId = 2;

  // Static references used by the action callback. Must be static because
  // awesome_notifications invokes the handler as a top-level entry point.
  static GoalRepository? _repository;
  static FocusListService? _focus;
  static ValueNotifier<({String goalId, int seq, bool breakdown})?>?
      _goalNavNotifier;
  static int _navSeq = 0;

  // Signature of what's currently displayed so update() is a no-op when the
  // visible content hasn't changed — avoids redundant platform calls.
  String? _lastSignature;

  NotificationService({
    required ValueNotifier<({String goalId, int seq, bool breakdown})?>
        goalNavNotifier,
    required GoalRepository repository,
    required FocusListService focus,
  }) {
    _repository = repository;
    _focus = focus;
    _goalNavNotifier = goalNavNotifier;
  }

  Future<void> init() async {
    await AwesomeNotifications().initialize(
      null, // null = use the app's default launcher icon
      [
        NotificationChannel(
          channelKey: _channelKey,
          channelName: 'Focus reminder',
          channelDescription:
              'Ongoing, silent reminder of your current focus task',
          importance: NotificationImportance.Low,
          defaultPrivacy: NotificationPrivacy.Public,
          playSound: false,
          enableVibration: false,
          enableLights: false,
          onlyAlertOnce: true,
          channelShowBadge: false,
        ),
      ],
      debug: false,
    );

    // Drop pre-redesign artefacts: the old High-importance channel (which
    // re-alerted on every content change) and the separate scheduled
    // morning-prompt notification.
    await AwesomeNotifications().removeChannel(_legacyChannelKey);
    await AwesomeNotifications().removeChannel(_legacyMorningChannelKey);
    await AwesomeNotifications().cancel(_legacyMorningPromptId);

    await AwesomeNotifications().setListeners(
      onActionReceivedMethod: _onActionReceived,
    );

    // Request Android 13+ notification permission; no-op on older APIs.
    final allowed = await AwesomeNotifications().isNotificationAllowed();
    if (!allowed) {
      await AwesomeNotifications().requestPermissionToSendNotifications();
    }

    // Cold-start: app was launched by tapping a notification action.
    final initialAction = await AwesomeNotifications()
        .getInitialNotificationAction(removeFromActionEvents: true);
    if (initialAction != null) {
      await _onActionReceived(initialAction);
    }
  }

  /// Rebuilds the persistent notification from the focus list.
  ///
  /// Picks the top-priority goal that still has pending work and renders its
  /// step list as an expandable [NotificationLayout.Inbox]. When nothing is
  /// actionable the notification either shows the "plan your day" empty state
  /// (when [showEmptyPrompt] is true) or is dismissed.
  Future<void> update(
    List<ResolvedFocusGroup> groups, {
    bool showEmptyPrompt = false,
  }) async {
    // The focus = the first focused goal that still has a pending subtask.
    ResolvedFocusGroup? currentGroup;
    for (final g in groups) {
      if (g.subtasks.any((s) => s.state == SubTaskState.pending)) {
        currentGroup = g;
        break;
      }
    }

    if (currentGroup == null) {
      if (showEmptyPrompt) {
        await _postEmptyState();
      } else {
        await dismiss();
      }
      return;
    }

    final goal = currentGroup.goal;
    final pendingSteps =
        goal.subtasks.where((s) => s.state == SubTaskState.pending).toList();
    final current = pendingSteps.first;

    // Count other focused goals that still have pending work — surfaced as a
    // "+N more goals" hint so the user knows the queue isn't just this goal.
    var otherGoals = 0;
    for (final g in groups) {
      if (g.goal.goalId == goal.goalId) continue;
      if (g.subtasks.any((s) => s.state == SubTaskState.pending)) otherGoals++;
    }

    // Skip the platform call when nothing visible changed.
    final signature = [
      goal.goalId,
      current.subtaskId,
      pendingSteps.length,
      goal.subtasks.length,
      otherGoals,
    ].join('|');
    if (signature == _lastSignature) return;
    _lastSignature = signature;

    // Inbox lines: current step (○ — the actionable hollow ring, matches the
    // widget's ic_widget_check_active drawable) first, then upcoming pending
    // steps (· — small muted dot, matches ic_widget_check_locked).
    const maxLines = 6;
    final lines = <String>[];
    for (var i = 0; i < pendingSteps.length && i < maxLines; i++) {
      final marker = i == 0 ? '○' : '·';
      lines.add('$marker  ${pendingSteps[i].description}');
    }
    final hidden = pendingSteps.length - lines.length;
    if (hidden > 0) {
      lines.add('     +$hidden more step${hidden == 1 ? '' : 's'}');
    }

    final done = goal.completedSubtaskCount;
    final total = goal.subtasks.length;
    final progress = '$done of $total steps done';
    final summary = otherGoals > 0
        ? '$progress  ·  +$otherGoals more goal${otherGoals == 1 ? '' : 's'}'
        : progress;

    final emoji = goal.emoji;
    final title = (emoji != null && emoji.isNotEmpty)
        ? '$emoji  ${goal.title}'
        : goal.title;
    final hasNext = pendingSteps.length > 1;

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: _notifId,
        channelKey: _channelKey,
        title: title,
        body: lines.join('\n'),
        summary: summary,
        notificationLayout: NotificationLayout.Inbox,
        category: NotificationCategory.Reminder,
        color: kBrandColor,
        payload: {
          'goalId': goal.goalId,
          'subtaskId': current.subtaskId,
        },
        autoDismissible: false,
        locked: true,
        showWhen: false,
      ),
      actionButtons: [
        NotificationActionButton(
          key: markDoneActionKey,
          label: hasNext ? 'Done · next step' : 'Mark done',
          actionType: ActionType.SilentAction,
          autoDismissible: false,
        ),
        NotificationActionButton(
          key: breakdownActionKey,
          label: 'Break it down',
          actionType: ActionType.Default,
          autoDismissible: false,
        ),
      ],
    );
  }

  /// Posts the "plan your day" empty state into the same notification slot.
  /// Used when the focus list is empty and the user wants the reminder.
  Future<void> _postEmptyState() async {
    const signature = 'empty';
    if (signature == _lastSignature) return;
    _lastSignature = signature;

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: _notifId,
        channelKey: _channelKey,
        title: 'Plan your day',
        body: 'Nothing in focus yet — tap to pick what to work on today.',
        notificationLayout: NotificationLayout.Default,
        category: NotificationCategory.Reminder,
        color: kBrandColor,
        autoDismissible: false,
        locked: true,
        showWhen: false,
      ),
    );
  }

  Future<void> dismiss() async {
    await AwesomeNotifications().cancel(_notifId);
    _lastSignature = null;
  }

  // Must be a static method annotated with @pragma('vm:entry-point') so the
  // Dart tree-shaker keeps it in release builds and awesome_notifications can
  // invoke it from its plugin entry point.
  @pragma('vm:entry-point')
  static Future<void> _onActionReceived(ReceivedAction action) async {
    final goalId = action.payload?['goalId'];
    final subtaskId = action.payload?['subtaskId'];

    if (action.buttonKeyPressed == markDoneActionKey) {
      if (goalId == null || subtaskId == null) return;
      var repo = _repository;
      var focus = _focus;
      if (repo == null || focus == null) {
        // The app process is dead — bootstrap a throwaway service stack so
        // the completion still persists. The notification refreshes itself
        // the next time the app is opened.
        repo = await HiveGoalRepository.init();
        focus = await FocusListService.init();
      }
      try {
        GoalService(repo, focus).completeSubTask(goalId, subtaskId);
      } catch (_) {
        // Out-of-order completion or a stale id — nothing to do.
      }
      // Completing from the notification is deliberately passive: no
      // navigation. The persistent notification updates in place.
      return;
    }

    if (action.buttonKeyPressed == breakdownActionKey) {
      // Breaking a step down needs the in-app editor, so this button opens
      // the app (ActionType.Default) and routes to the goal.
      if (goalId != null) {
        _goalNavNotifier?.value = (
          goalId: goalId,
          seq: ++_navSeq,
          breakdown: true,
        );
      }
      return;
    }

    // Notification body tapped — navigate to the goal.
    if (goalId != null) {
      _goalNavNotifier?.value = (
        goalId: goalId,
        seq: ++_navSeq,
        breakdown: false,
      );
    }
  }
}
