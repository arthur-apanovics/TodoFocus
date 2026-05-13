import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/goal.dart';
import 'goal_repository.dart';
import 'goal_service.dart';

class NotificationService {
  static const String markDoneActionId = 'mark_done';
  static const String breakdownActionId = 'breakdown';
  static const int _notifId = 1;
  static const String _channelId = 'focus_task_v2';
  static const String _channelName = 'Focus Task';

  final FlutterLocalNotificationsPlugin _plugin;
  final ValueNotifier<int> _tabNotifier;
  // Carries the goal to navigate to. The int seq increments on every tap so
  // repeated taps on the same goal each fire the notifier.
  final ValueNotifier<(String goalId, int seq)?> _goalNavNotifier;
  final GoalRepository _repository;

  int _navSeq = 0;

  // Track what's currently shown so update() is a no-op when content hasn't
  // changed. Without this, every app resume triggers show() which Android
  // treats as a new notification event — sound and vibration included.
  String? _shownGoalId;
  String? _shownSubtaskId;

  NotificationService({
    required ValueNotifier<int> tabNotifier,
    required ValueNotifier<(String, int)?> goalNavNotifier,
    required GoalRepository repository,
  })  : _plugin = FlutterLocalNotificationsPlugin(),
        _tabNotifier = tabNotifier,
        _goalNavNotifier = goalNavNotifier,
        _repository = repository;

  Future<void> init() async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    // Importance must be set on channel creation and cannot be changed
    // once the channel exists on the device.
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Shows your current active subtask',
        importance: Importance.high,
      ),
    );

    // Request Android 13+ (API 33) notification permission.
    // No-op on older APIs.
    await androidPlugin?.requestNotificationsPermission();

    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: _onResponse,
    );

    // When the app is killed, onDidReceiveNotificationResponse never fires.
    // Instead, check whether the app was cold-started by a notification tap
    // and replay the action now that the repository is ready.
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      final response = launchDetails!.notificationResponse;
      if (response != null) _onResponse(response);
    }
  }

  Future<void> update(List<Goal> todayQueue) async {
    if (todayQueue.isEmpty) {
      await _plugin.cancel(_notifId);
      _shownGoalId = null;
      _shownSubtaskId = null;
      return;
    }

    final goal = todayQueue.first;
    final current = goal.currentSubTask;

    if (current == null) {
      await _plugin.cancel(_notifId);
      _shownGoalId = null;
      _shownSubtaskId = null;
      return;
    }

    // Skip if the visible content hasn't changed — avoids re-triggering
    // sound/vibration on app resume when the task is still the same.
    if (goal.goalId == _shownGoalId && current.subtaskId == _shownSubtaskId) {
      return;
    }
    _shownGoalId = goal.goalId;
    _shownSubtaskId = current.subtaskId;

    await _plugin.show(
      _notifId,
      '❯ ${current.description}',
      '↳ ${goal.nextSubTask != null ? goal.nextSubTask!.description : 'Completed!'}',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Shows your current active subtask',
          importance: Importance.high,
          priority: Priority.high,
          ongoing: true,
          autoCancel: false,
          showWhen: false,
          subText: goal.title,
          actions: [
            AndroidNotificationAction(
              markDoneActionId,
              goal.nextSubTask != null ? 'Next step' : 'Finish goal',
              showsUserInterface: true,
              cancelNotification: false,
            ),
            const AndroidNotificationAction(
              breakdownActionId,
              'Break it down',
              showsUserInterface: true,
              cancelNotification: false,
            ),
          ],
        ),
      ),
      payload: goal.goalId,
    );
  }

  Future<void> dismiss() => _plugin.cancel(_notifId);

  void _onResponse(NotificationResponse response) {
    if (response.actionId == markDoneActionId) {
      if (response.payload != null) {
        GoalService(_repository).completeCurrentSubTask(response.payload!);
        _goalNavNotifier.value = (response.payload!, ++_navSeq);
      }
      return;
    }

    if (response.actionId == breakdownActionId) {
      if (response.payload != null) {
        _goalNavNotifier.value = (response.payload!, ++_navSeq);
      }
      return;
    }

    // Notification body tapped — open the Focus tab.
    _tabNotifier.value = 0;
  }
}
