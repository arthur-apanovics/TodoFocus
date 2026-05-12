import 'package:collection/collection.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:todo_app/services/sample_data.dart';
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

  HiveGoalRepository(this._box) {
    if (_box.isEmpty) {
      // Key by goalId to match save()/delete() — otherwise addAll uses
      // auto-incrementing integer keys and later saves create duplicates.
      _box.putAll({
        for (final goal in SampleData.goals) goal.goalId: _toDto(goal),
      });
    }
  }

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

  // --- Mapping: DTO → Domain ---

  Goal _toDomain(GoalDto dto) {
    return Goal(
      goalId: dto.goalId,
      title: dto.title,
      notes: dto.notes,
      status: GoalStatus.values.byName(dto.status),
      dueDate: dto.dueDate,
      isFocusedToday: dto.isFocusedToday,
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
      ..dueDate = goal.dueDate
      ..isFocusedToday = goal.isFocusedToday
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
