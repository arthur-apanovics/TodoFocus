import 'package:hive_flutter/hive_flutter.dart';
import 'sub_task_dto.dart';

part 'goal_dto.g.dart';

@HiveType(typeId: 0)
class GoalDto extends HiveObject {
  @HiveField(0)
  late String goalId;

  @HiveField(1)
  late String title;

  @HiveField(2)
  late String notes;

  @HiveField(3)
  late String status; // enum stored as string

  @HiveField(4)
  DateTime? dueDate;

  @HiveField(5)
  late List<SubTaskDto> subtasks;
}
