import 'package:hive_flutter/hive_flutter.dart';

part 'sub_task_dto.g.dart'; // generated file

@HiveType(typeId: 1)
class SubTaskDto extends HiveObject {
  @HiveField(0)
  late String subtaskId;

  @HiveField(1)
  late String description;

  @HiveField(2)
  late String state; // stored as string, mapped to enum in repository

  @HiveField(3)
  late DateTime assignedDate;

  @HiveField(4)
  DateTime? completionDate;

  @HiveField(5)
  late DateTime lastSeenDate;

  @HiveField(6)
  int? effortEstimate;
}
