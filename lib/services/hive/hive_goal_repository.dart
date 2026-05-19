import 'package:collection/collection.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../models/enums.dart';
import '../../models/goal.dart';
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
      ..subtasks = goal.subtasks.map(_subTaskToDto).toList();
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
      ..effortEstimate = subtask.effortEstimate;
  }

  // --- Static initialisation helper ---
  // Called once at app startup before the repository is registered
  static Future<HiveGoalRepository> init() async {
    await Hive.initFlutter();
    Hive.registerAdapter(GoalDtoAdapter());
    Hive.registerAdapter(SubTaskDtoAdapter());
    final box = await Hive.openBox<GoalDto>(_boxName);

    return HiveGoalRepository(box);
  }
}
