import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../models/enums.dart';
import '../../models/goal.dart';
import '../../models/recurrence.dart';
import '../../models/sub_task.dart';
import '../goal_repository.dart';
import 'goal_dto.dart';
import 'sub_task_dto.dart';

class HiveGoalRepository extends GoalRepository {
  static const String _boxName = 'goals';

  // The box is late because it's opened asynchronously before this
  // repository is used — see main.dart initialisation below
  late final Box<GoalDto> _box;

  HiveGoalRepository(this._box, {bool seed = true});

  // --- GoalRepository implementation ---

  @override
  List<Goal> get all => _box.values.map(_toDomain).toList();

  @override
  Goal? findById(String goalId) {
    final dto = _box.values.firstWhereOrNull((dto) => dto.goalId == goalId);
    return dto != null ? _toDomain(dto) : null;
  }

  @override
  void save(Goal goal) {
    _box.put(goal.goalId, _toDto(goal));
    notifyListeners();
  }

  @override
  void delete(String goalId) {
    // Hive uses the key we passed to put() — which is goalId
    _box.delete(goalId);
    notifyListeners();
  }

  @override
  Future<void> clear() async {
    await _box.clear();
    notifyListeners();
  }

  @override
  List<Map<String, dynamic>> exportToJson() =>
      _box.values.map((dto) => _toDomain(dto).toJson()).toList();

  @override
  Future<({int imported, int skipped})> importFromJson(
    List<dynamic> data,
  ) async {
    int imported = 0;
    int skipped = 0;
    await _box.clear();
    for (final item in data) {
      try {
        final goal = Goal.fromJson(item as Map<String, dynamic>);
        await _box.put(goal.goalId, _toDto(goal));
        imported++;
      } catch (_) {
        skipped++;
      }
    }
    notifyListeners();
    return (imported: imported, skipped: skipped);
  }

  // --- Mapping: DTO → Domain ---
  //
  // IMPORTANT: when you add a field to GoalDto or Goal, update BOTH _toDomain
  // and _toDto below, then add the field to the 'full field round-trip' test
  // in test/services/hive/hive_goal_repository_test.dart — that test is the
  // compile-time-equivalent enforcement for the mapping layer.

  Goal _toDomain(GoalDto dto) {
    return Goal(
      goalId: dto.goalId,
      title: dto.title,
      notes: dto.notes,
      // Legacy "paused" records (from before pause was removed) silently
      // become active. The next save() rewrites them with the new value.
      status: switch (dto.status) {
        'paused' => GoalStatus.active,
        _ => GoalStatus.values.byName(dto.status),
      },
      difficulty: GoalDifficulty.values.asNameMap()[dto.difficulty ?? ''] ??
          GoalDifficulty.easy,
      dueDate: dto.dueDate,
      emoji: dto.emoji,
      subtasks: dto.subtasks.map(_subTaskToDomain).toList(),
      recurrence: dto.recurrenceJson != null
          ? Recurrence.fromJson(
              jsonDecode(dto.recurrenceJson!) as Map<String, dynamic>)
          : null,
      nextOccurrenceAt: dto.nextOccurrenceAt,
      lastIterationSummary: dto.lastIterationSummary ?? '',
      lastResumedAt: dto.lastResumedAt,
      createdAt: dto.createdAt,
      showTimeEstimatesOverride: dto.showTimeEstimatesOverride,
      isDailyTaskList: dto.isDailyTaskList ?? false,
    );
  }

  SubTask _subTaskToDomain(SubTaskDto dto) {
    return SubTask(
      subtaskId: dto.subtaskId,
      description: dto.description,
      state: SubTaskState.values.byName(dto.state),
      assignedDate: dto.assignedDate,
      completionDate: dto.completionDate,
      lastSeenDate: dto.lastSeenDate,
      effortEstimate: dto.effortEstimate,
      snoozedUntil: dto.snoozedUntil,
      notifyOnWake: dto.notifyOnWake ?? false,
      autoSleepDuration: dto.autoSleepSeconds != null
          ? Duration(seconds: dto.autoSleepSeconds!)
          : null,
      estimatedMinutes: dto.estimatedMinutes,
    );
  }

  // --- Mapping: Domain → DTO ---

  GoalDto _toDto(Goal goal) {
    final dto = GoalDto()
      ..goalId = goal.goalId
      ..title = goal.title
      ..notes = goal.notes
      ..status = goal.status.name
      ..difficulty = goal.difficulty.name
      ..dueDate = goal.dueDate
      ..emoji = goal.emoji
      ..subtasks = goal.subtasks.map(_subTaskToDto).toList()
      ..recurrenceJson = goal.recurrence != null
          ? jsonEncode(goal.recurrence!.toJson())
          : null
      ..nextOccurrenceAt = goal.nextOccurrenceAt
      ..lastIterationSummary =
          goal.lastIterationSummary.isEmpty ? null : goal.lastIterationSummary
      ..lastResumedAt = goal.lastResumedAt
      ..createdAt = goal.createdAt
      ..showTimeEstimatesOverride = goal.showTimeEstimatesOverride
      ..isDailyTaskList = goal.isDailyTaskList ? true : null;
    return dto;
  }

  SubTaskDto _subTaskToDto(SubTask subtask) {
    return SubTaskDto()
      ..subtaskId = subtask.subtaskId
      ..description = subtask.description
      ..state = subtask.state.name
      ..assignedDate = subtask.assignedDate
      ..completionDate = subtask.completionDate
      ..lastSeenDate = subtask.lastSeenDate
      ..effortEstimate = subtask.effortEstimate
      ..snoozedUntil = subtask.snoozedUntil
      ..notifyOnWake = subtask.notifyOnWake
      ..autoSleepSeconds = subtask.autoSleepDuration?.inSeconds
      ..estimatedMinutes = subtask.estimatedMinutes;
  }

  // --- Static initialisation helper ---
  // Called at app startup, and again from the home-widget background isolate.
  // Adapter registration is guarded so a second call (in a fresh isolate, or
  // after a hot restart) doesn't throw "already registered".
  static Future<HiveGoalRepository> init() async {
    await Hive.initFlutter();
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(GoalDtoAdapter());
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(SubTaskDtoAdapter());
    final box = await Hive.openBox<GoalDto>(_boxName);

    return HiveGoalRepository(box);
  }
}
