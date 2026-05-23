import 'package:hive_flutter/hive_flutter.dart';
import 'sub_task_dto.dart';

part 'goal_dto.g.dart';

// Field index registry — NEVER reuse a retired index
// 0: goalId               (active)
// 1: title                (active)
// 2: notes                (active)
// 3: status               (active)
// 4: dueDate              (active)
// 5: subtasks             (active)
// 6: isFocusedToday       (RETIRED — focus moved to FocusListService)
// 7: todayOrder           (RETIRED — focus moved to FocusListService)
// 8: difficulty           (active)
// 9: emoji                (active)
// 10: recurrenceJson      (active)
// 11: nextOccurrenceAt    (active)
// 12: lastIterationSummary (active)
// 13: lastResumedAt       (active)
// 14: createdAt           (active)
// 15: showTimeEstimatesOverride (active)
// Next available: 16

@HiveType(typeId: 0)
class GoalDto extends HiveObject {
  @HiveField(0)
  late String goalId;

  @HiveField(1)
  late String title;

  @HiveField(2)
  late String notes;

  @HiveField(3)
  late String status;

  @HiveField(4)
  DateTime? dueDate;

  @HiveField(5)
  late List<SubTaskDto> subtasks;

  @HiveField(8)
  String? difficulty;

  @HiveField(9)
  String? emoji;

  @HiveField(10)
  String? recurrenceJson;

  @HiveField(11)
  DateTime? nextOccurrenceAt;

  @HiveField(12)
  String? lastIterationSummary;

  @HiveField(13)
  DateTime? lastResumedAt;

  @HiveField(14)
  DateTime? createdAt;

  @HiveField(15)
  bool? showTimeEstimatesOverride;
}
