import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/enums.dart';
import '../models/goal.dart';
import 'focus_list_service.dart';

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
  final FocusListService _focus;

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
    required FocusListService focus,
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
        _focus = focus,
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
    // Snapshot the goals that had at least one focused subtask before the
    // wipe so the urgency-sort heuristic can keep "previously assigned"
    // goals near the top of the list afterwards.
    final priorGoalIds = _focus.groups.map((g) => g.goalId).toList();
    _previouslyAssigned = priorGoalIds;
    await _box.put(_prevAssignedKey, priorGoalIds.join(','));

    await _focus.clearAll();

    _lastResetDate = _dateString(now);
    await _box.put(_lastResetDateKey, _lastResetDate!);
    notifyListeners();
  }

  /// Returns [goals] sorted according to [order].
  /// Date-added preserves the repository's insertion order unchanged.
  /// Urgency and smart use identical logic: near-deadline goals first (by
  /// due date ascending), then previously-assigned goals, then the rest.
  ///
  /// Across every sort order, goals **on hold** (current subtask snoozed)
  /// are demoted to the bottom — they have nothing actionable, so they
  /// shouldn't compete for top-of-list real estate.
  List<Goal> sortGoals(List<Goal> goals, GoalSortOrder order) {
    if (order == GoalSortOrder.dateAdded) {
      return _demoteOnHold([...goals]);
    }
    final sorted = [...goals];
    _applyUrgencySort(sorted);
    return _demoteOnHold(sorted);
  }

  /// Splits [goals] into labelled categories for the Smart sort view.
  ///
  /// Categories (in display order):
  ///   • **Resumed**     — a subtask just woke up OR the recurrence just
  ///                       reset within the last 24h. These are intentionally
  ///                       at the top so the user notices "this is back".
  ///   • **Urgent**      — due within [urgencyDays] days (sorted by due date).
  ///   • **In progress** — previously assigned to today's focus but not urgent.
  ///   • **Other**       — everything else.
  ///   • **On hold**     — current subtask is snoozed; nothing actionable.
  ///
  /// Empty categories are omitted. Within each bucket goals are ordered by
  /// [_applyUrgencySort] so the relative priority matches the flat sort.
  List<({String label, List<Goal> goals})> categorizeForSmart(
      List<Goal> goals) {
    final now = DateTime.now();
    final cutoff = DateTime(now.year, now.month, now.day + _urgencyDays);
    // "Recently resumed" window: a goal that woke up within this duration
    // gets its own top bucket. 24h covers the common "I snoozed it until
    // tomorrow" pattern without lingering for days.
    final resumeCutoff = now.subtract(const Duration(hours: 24));

    final resumed = <Goal>[];
    final urgent = <Goal>[];
    final inProgress = <Goal>[];
    final other = <Goal>[];
    final onHold = <Goal>[];

    for (final g in goals) {
      if (g.isOnHold) {
        onHold.add(g);
      } else if (g.lastResumedAt != null &&
          g.lastResumedAt!.isAfter(resumeCutoff)) {
        resumed.add(g);
      } else if (g.dueDate != null && !g.dueDate!.isAfter(cutoff)) {
        urgent.add(g);
      } else if (_previouslyAssigned.contains(g.goalId)) {
        inProgress.add(g);
      } else {
        other.add(g);
      }
    }

    // Within each non-on-hold bucket, apply urgency ordering for consistency.
    _applyUrgencySort(resumed);
    _applyUrgencySort(urgent);
    _applyUrgencySort(inProgress);
    // "other" stays in insertion order (stable).
    // "onHold" stays in insertion order — nothing actionable, no ranking needed.

    return [
      if (resumed.isNotEmpty) (label: 'Resumed', goals: resumed),
      if (urgent.isNotEmpty) (label: 'Urgent', goals: urgent),
      if (inProgress.isNotEmpty) (label: 'In progress', goals: inProgress),
      if (other.isNotEmpty) (label: 'Other', goals: other),
      if (onHold.isNotEmpty) (label: 'On hold', goals: onHold),
    ];
  }

  /// Stably partitions [goals] so on-hold goals (current subtask snoozed)
  /// sink to the bottom. Used by the flat sort orders to keep "nothing
  /// actionable" goals out of the way without changing relative priority.
  List<Goal> _demoteOnHold(List<Goal> goals) {
    final active = <Goal>[];
    final held = <Goal>[];
    for (final g in goals) {
      (g.isOnHold ? held : active).add(g);
    }
    return [...active, ...held];
  }

  void _applyUrgencySort(List<Goal> goals) {
    final now = DateTime.now();
    final cutoff = DateTime(now.year, now.month, now.day + _urgencyDays);
    // Goals woken / reset within this window get a priority boost so the
    // user notices "hey, this is back" the next time they look at the list.
    final resumeCutoff = now.subtract(const Duration(hours: 24));

    goals.sort((a, b) {
      // 1. Recently resumed goals (snooze just elapsed / recurrence cycled)
      //    rise above everything except more-urgent due dates below.
      final aResumed = a.lastResumedAt != null &&
          a.lastResumedAt!.isAfter(resumeCutoff);
      final bResumed = b.lastResumedAt != null &&
          b.lastResumedAt!.isAfter(resumeCutoff);

      // 2. Urgent = has a due date within the urgency window.
      final aUrgent = a.dueDate != null && !a.dueDate!.isAfter(cutoff);
      final bUrgent = b.dueDate != null && !b.dueDate!.isAfter(cutoff);

      // Urgent always wins over Resumed — a deadline beats a wake-up.
      if (aUrgent != bUrgent) return aUrgent ? -1 : 1;
      if (aUrgent) return a.dueDate!.compareTo(b.dueDate!);

      // Resumed beats In-progress and Other.
      if (aResumed != bResumed) return aResumed ? -1 : 1;
      if (aResumed) {
        // More recently resumed first.
        return b.lastResumedAt!.compareTo(a.lastResumedAt!);
      }

      final aPrev = _previouslyAssigned.contains(a.goalId);
      final bPrev = _previouslyAssigned.contains(b.goalId);
      if (aPrev != bPrev) return aPrev ? -1 : 1;

      return 0; // stable sort preserves insertion order for remaining goals
    });
  }

  static String _dateString(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  static Future<DailyResetService> init(FocusListService focus) async {
    final box = await Hive.openBox<String>(_boxName);

    final rawPrev = box.get(_prevAssignedKey, defaultValue: '') ?? '';
    final previouslyAssigned = rawPrev.isEmpty
        ? <String>[]
        : rawPrev.split(',').where((s) => s.isNotEmpty).toList();

    return DailyResetService._(
      box: box,
      focus: focus,
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
