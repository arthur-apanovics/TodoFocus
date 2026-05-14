import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import '../models/goal.dart';
import 'goal_repository.dart';
import 'goal_service.dart';

class NotificationService {
  static const String markDoneActionKey = 'mark_done';
  static const String breakdownActionKey = 'breakdown';
  static const int _notifId = 1;
  static const String _channelKey = 'focus_task';
  static const String _channelName = 'Focus Task';

  // Static references used by the action callback. Must be static because
  // awesome_notifications invokes the handler as a top-level entry point.
  static GoalRepository? _repository;
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
  }) {
    _repository = repository;
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

  Future<void> update(List<Goal> todayQueue) async {
    if (todayQueue.isEmpty) {
      await dismiss();
      return;
    }

    final goal = todayQueue.first;
    final current = goal.currentSubTask;

    if (current == null) {
      await dismiss();
      return;
    }

    // Skip re-posting unchanged content — avoids sound/vibration on resume.
    if (goal.goalId == _shownGoalId && current.subtaskId == _shownSubtaskId) {
      return;
    }
    _shownGoalId = goal.goalId;
    _shownSubtaskId = current.subtaskId;

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: _notifId,
        channelKey: _channelKey,
        title: '❯ ${current.description}',
        body: goal.nextSubTask != null
            ? '↳ ${goal.nextSubTask!.description}'
            : '↳ Completed!',
        summary: goal.title,
        payload: {'goalId': goal.goalId},
        notificationLayout: NotificationLayout.Default,
        autoDismissible: false,
        locked: true,
        showWhen: false,
      ),
      actionButtons: [
        NotificationActionButton(
          key: markDoneActionKey,
          label: goal.nextSubTask != null ? 'Next step' : 'Finish goal',
          actionType: ActionType.SilentAction,
        ),
        NotificationActionButton(
          key: breakdownActionKey,
          label: 'Break it down',
          actionType: ActionType.SilentAction,
        ),
      ],
    );
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

    if (action.buttonKeyPressed == markDoneActionKey) {
      if (goalId != null && _repository != null) {
        GoalService(_repository!).completeCurrentSubTask(goalId);
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
