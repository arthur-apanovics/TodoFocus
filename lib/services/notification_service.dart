import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import '../models/enums.dart';
import '../models/goal.dart';
import '../models/sub_task.dart';
import 'focus_list_service.dart';
import 'goal_repository.dart';
import 'goal_service.dart';

class NotificationService {
  static const String markDoneActionKey = 'mark_done';
  static const String breakdownActionKey = 'breakdown';
  static const int _notifId = 1;
  static const int _morningPromptId = 2;
  static const String _channelKey = 'focus_task';
  static const String _channelName = 'Focus Task';
  static const String _morningChannelKey = 'morning_prompt';
  static const String _morningChannelName = 'Morning Prompt';

  // Static references used by the action callback. Must be static because
  // awesome_notifications invokes the handler as a top-level entry point.
  static GoalRepository? _repository;
  static FocusListService? _focus;
  static ValueNotifier<({String goalId, int seq, bool breakdown})?>?
      _goalNavNotifier;
  static int _navSeq = 0;

  // Track what's currently shown so update() is a no-op when content hasn't
  // changed — avoids re-triggering sound/vibration on every app resume.
  String? _shownGoalId;
  String? _shownSubtaskId;

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
          channelName: _channelName,
          channelDescription: 'Shows your current active subtask',
          importance: NotificationImportance.High,
          defaultPrivacy: NotificationPrivacy.Public,
        ),
        NotificationChannel(
          channelKey: _morningChannelKey,
          channelName: _morningChannelName,
          channelDescription: 'Daily reminder to assign tasks for the day',
          importance: NotificationImportance.Default,
          defaultPrivacy: NotificationPrivacy.Public,
        ),
      ],
      debug: false,
    );

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

  /// Rebuilds the persistent notification from the focus list. Walks the
  /// resolved groups in priority order, picks the first two pending subtasks
  /// (current + peek), and posts. Both "current" and "peek" may belong to
  /// the same or different goals.
  Future<void> update(List<ResolvedFocusGroup> groups) async {
    final pendings = <({Goal goal, SubTask subtask})>[];
    for (final g in groups) {
      for (final s in g.subtasks) {
        if (s.state == SubTaskState.pending) {
          pendings.add((goal: g.goal, subtask: s));
          if (pendings.length >= 2) break;
        }
      }
      if (pendings.length >= 2) break;
    }
    if (pendings.isEmpty) {
      await dismiss();
      return;
    }

    final current = pendings[0];
    final next = pendings.length > 1 ? pendings[1] : null;

    // Skip re-posting unchanged content — avoids sound/vibration on resume.
    if (current.goal.goalId == _shownGoalId &&
        current.subtask.subtaskId == _shownSubtaskId) {
      return;
    }
    _shownGoalId = current.goal.goalId;
    _shownSubtaskId = current.subtask.subtaskId;

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: _notifId,
        channelKey: _channelKey,
        title: current.goal.title,
        body: next != null
            ? '❯ ${current.subtask.description}\n↳ ${next.subtask.description}'
            : '❯ ${current.subtask.description}',
        payload: {
          'goalId': current.goal.goalId,
          'subtaskId': current.subtask.subtaskId,
        },
        notificationLayout: NotificationLayout.Default,
        autoDismissible: false,
        locked: true,
        showWhen: false,
      ),
      actionButtons: [
        NotificationActionButton(
          key: markDoneActionKey,
          label: next != null ? 'Next step' : 'Mark done',
          actionType: ActionType.SilentAction,
          autoDismissible: false,
        ),
        NotificationActionButton(
          key: breakdownActionKey,
          label: 'Break it down',
          actionType: ActionType.SilentAction,
          autoDismissible: false,
        ),
      ],
    );
  }

  /// Shows a persistent "Assign tasks" notification after a daily reset.
  Future<void> showAssignTasksPrompt() async {
    _shownGoalId = null;
    _shownSubtaskId = null;
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: _notifId,
        channelKey: _channelKey,
        title: 'Plan your day',
        body: 'Assign tasks to focus on today',
        notificationLayout: NotificationLayout.Default,
        autoDismissible: true,
        locked: false,
        showWhen: false,
      ),
    );
  }

  /// Schedules (or re-schedules) the daily morning prompt notification.
  Future<void> scheduleMorningPrompt(int hour, int minute) async {
    await AwesomeNotifications().cancel(_morningPromptId);
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: _morningPromptId,
        channelKey: _morningChannelKey,
        title: 'Good morning!',
        body: 'Assign tasks to focus on today',
        notificationLayout: NotificationLayout.Default,
      ),
      schedule: NotificationCalendar(
        hour: hour,
        minute: minute,
        second: 0,
        millisecond: 0,
        repeats: true,
        allowWhileIdle: true,
        preciseAlarm: false,
      ),
    );
  }

  /// Cancels the morning prompt if it was scheduled.
  Future<void> cancelMorningPrompt() async {
    await AwesomeNotifications().cancel(_morningPromptId);
  }

  Future<void> dismiss() async {
    await AwesomeNotifications().cancel(_notifId);
    _shownGoalId = null;
    _shownSubtaskId = null;
  }

  // Must be a static method annotated with @pragma('vm:entry-point') so the
  // Dart tree-shaker keeps it in release builds and awesome_notifications can
  // invoke it from its plugin entry point.
  @pragma('vm:entry-point')
  static Future<void> _onActionReceived(ReceivedAction action) async {
    final goalId = action.payload?['goalId'];
    final subtaskId = action.payload?['subtaskId'];

    if (action.buttonKeyPressed == markDoneActionKey) {
      if (goalId != null && subtaskId != null && _repository != null) {
        final svc = _focus != null
            ? GoalService(_repository!, _focus!)
            : null;
        svc?.completeSubTask(goalId, subtaskId);
        _goalNavNotifier?.value = (
          goalId: goalId,
          seq: ++_navSeq,
          breakdown: false,
        );
      }
      return;
    }

    if (action.buttonKeyPressed == breakdownActionKey) {
      if (goalId != null) {
        _goalNavNotifier?.value = (
          goalId: goalId,
          seq: ++_navSeq,
          breakdown: true,
        );
      }
      return;
    }

    // Notification body tapped — navigate to the goal detail screen.
    if (goalId != null) {
      _goalNavNotifier?.value = (
        goalId: goalId,
        seq: ++_navSeq,
        breakdown: false,
      );
    }
  }
}
