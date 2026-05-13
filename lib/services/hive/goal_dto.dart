import 'package:hive_flutter/hive_flutter.dart';
import 'sub_task_dto.dart';

part 'goal_dto.g.dart';

// Field index registry — NEVER reuse a retired index
// 0: goalId          (active)
// 1: title           (active)
// 2: notes           (active)
// 3: status          (active)
// 4: dueDate         (active)
// 5: subtasks        (active)
// 6: isFocusedToday  (active)
// 7: todayOrder      (active)
// Next available: 8

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

  @HiveField(6)
  bool isFocusedToday = false;

  @HiveField(7)
  int todayOrder = 0;
}
