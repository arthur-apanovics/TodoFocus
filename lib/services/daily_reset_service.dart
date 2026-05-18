import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/enums.dart';
import '../models/goal.dart';
import 'goal_repository.dart';

class DailyResetService extends ChangeNotifier {
  static const _boxName = 'app_settings';
  static const _resetEnabledKey = 'daily_reset_enabled';
  static const _resetHourKey = 'daily_reset_hour';
  static const _resetMinuteKey = 'daily_reset_minute';
  static const _lastResetDateKey = 'daily_reset_last_date';
  static const _prevAssignedKey = 'daily_reset_prev_assigned';
  static const _morningPromptEnabledKey = 'morning_prompt_enabled';
  static const _morningPromptHourKey = 'morning_prompt_hour';
  static const _morningPromptMinuteKey = 'morning_prompt_minute';
  static const _urgencyDaysKey = 'urgency_days';

  final Box<String> _box;
  final GoalRepository _repo;

  bool _resetEnabled;
  int _resetHour;
  int _resetMinute;
  String? _lastResetDate;
  List<String> _previouslyAssigned;
  bool _morningPromptEnabled;
  int _morningPromptHour;
  int _morningPromptMinute;
  int _urgencyDays;
  DailyResetService._({
    required Box<String> box,
    required GoalRepository repo,
    required bool resetEnabled,
    required int resetHour,
    required int resetMinute,
    required String? lastResetDate,
    required List<String> previouslyAssigned,
    required bool morningPromptEnabled,
    required int morningPromptHour,
    required int morningPromptMinute,
    required int urgencyDays,
  })  : _box = box,
        _repo = repo,
        _resetEnabled = resetEnabled,
        _resetHour = resetHour,
        _resetMinute = resetMinute,
        _lastResetDate = lastResetDate,
        _previouslyAssigned = previouslyAssigned,
        _morningPromptEnabled = morningPromptEnabled,
        _morningPromptHour = morningPromptHour,
        _morningPromptMinute = morningPromptMinute,
        _urgencyDays = urgencyDays;

  bool get resetEnabled => _resetEnabled;
  TimeOfDay get resetTime => TimeOfDay(hour: _resetHour, minute: _resetMinute);
  bool get morningPromptEnabled => _morningPromptEnabled;
  TimeOfDay get morningPromptTime =>
      TimeOfDay(hour: _morningPromptHour, minute: _morningPromptMinute);
  int get urgencyDays => _urgencyDays;
  List<String> get previouslyAssigned => List.unmodifiable(_previouslyAssigned);

  Future<void> setResetEnabled(bool value) async {
    _resetEnabled = value;
    await _box.put(_resetEnabledKey, value.toString());
    notifyListeners();
  }

  Future<void> setResetTime(TimeOfDay time) async {
    _resetHour = time.hour;
    _resetMinute = time.minute;
    await _box.put(_resetHourKey, time.hour.toString());
    await _box.put(_resetMinuteKey, time.minute.toString());
    notifyListeners();
  }

  Future<void> setMorningPromptEnabled(bool value) async {
    _morningPromptEnabled = value;
    await _box.put(_morningPromptEnabledKey, value.toString());
    notifyListeners();
  }

  Future<void> setMorningPromptTime(TimeOfDay time) async {
    _morningPromptHour = time.hour;
    _morningPromptMinute = time.minute;
    await _box.put(_morningPromptHourKey, time.hour.toString());
    await _box.put(_morningPromptMinuteKey, time.minute.toString());
    notifyListeners();
  }

  Future<void> setUrgencyDays(int days) async {
    _urgencyDays = days;
    await _box.put(_urgencyDaysKey, days.toString());
    notifyListeners();
  }

  /// Checks if a reset is due and performs it. Returns true if reset ran.
  Future<bool> checkAndReset() async {
    if (!_resetEnabled) return false;

    final now = DateTime.now();
    final today = _dateString(now);
    if (_lastResetDate == today) return false;

    final resetMinutes = _resetHour * 60 + _resetMinute;
    final nowMinutes = now.hour * 60 + now.minute;
    if (nowMinutes < resetMinutes) return false;

    await _performReset(now);
    return true;
  }

  Future<void> _performReset(DateTime now) async {
    final focused = _repo.all
        .where((g) => g.isFocusedToday)
        .map((g) => g.goalId)
        .toList();
    _previouslyAssigned = focused;
    await _box.put(_prevAssignedKey, focused.join(','));

    for (final goal in _repo.all.where((g) => g.isFocusedToday).toList()) {
      goal.isFocusedToday = false;
      goal.todayOrder = 0;
      _repo.save(goal);
    }

    _lastResetDate = _dateString(now);
    await _box.put(_lastResetDateKey, _lastResetDate!);
    notifyListeners();
  }

  /// Returns [goals] sorted according to [order].
  /// Date-added preserves the repository's insertion order unchanged.
  /// Urgency and smart use identical logic: near-deadline goals first (by
  /// due date ascending), then previously-assigned goals, then the rest.
  List<Goal> sortGoals(List<Goal> goals, GoalSortOrder order) {
    if (order == GoalSortOrder.dateAdded) return goals;
    final sorted = [...goals];
    _applyUrgencySort(sorted);
    return sorted;
  }

  void _applyUrgencySort(List<Goal> goals) {
    final now = DateTime.now();
    final cutoff = DateTime(now.year, now.month, now.day + _urgencyDays);

    goals.sort((a, b) {
      final aUrgent = a.dueDate != null && !a.dueDate!.isAfter(cutoff);
      final bUrgent = b.dueDate != null && !b.dueDate!.isAfter(cutoff);

      if (aUrgent != bUrgent) return aUrgent ? -1 : 1;
      if (aUrgent) return a.dueDate!.compareTo(b.dueDate!);

      final aPrev = _previouslyAssigned.contains(a.goalId);
      final bPrev = _previouslyAssigned.contains(b.goalId);
      if (aPrev != bPrev) return aPrev ? -1 : 1;

      return 0; // stable sort preserves insertion order for remaining goals
    });
  }

  static String _dateString(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  static Future<DailyResetService> init(GoalRepository repo) async {
    final box = await Hive.openBox<String>(_boxName);

    final rawPrev = box.get(_prevAssignedKey, defaultValue: '') ?? '';
    final previouslyAssigned = rawPrev.isEmpty
        ? <String>[]
        : rawPrev.split(',').where((s) => s.isNotEmpty).toList();

    return DailyResetService._(
      box: box,
      repo: repo,
      resetEnabled: box.get(_resetEnabledKey) == 'true',
      resetHour: int.tryParse(box.get(_resetHourKey) ?? '') ?? 3,
      resetMinute: int.tryParse(box.get(_resetMinuteKey) ?? '') ?? 0,
      lastResetDate: box.get(_lastResetDateKey),
      previouslyAssigned: previouslyAssigned,
      morningPromptEnabled: box.get(_morningPromptEnabledKey) == 'true',
      morningPromptHour: int.tryParse(box.get(_morningPromptHourKey) ?? '') ?? 8,
      morningPromptMinute:
          int.tryParse(box.get(_morningPromptMinuteKey) ?? '') ?? 0,
      urgencyDays: int.tryParse(box.get(_urgencyDaysKey) ?? '') ?? 3,
    );
  }
}
