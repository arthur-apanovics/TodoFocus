import 'package:hive_flutter/hive_flutter.dart';

part 'sub_task_dto.g.dart'; // generated file

// Field index registry — NEVER reuse a retired index
// 0: subtaskId         (active)
// 1: description       (active)
// 2: state             (active) — values: "pending", "completed", "snoozed"
// 3: assignedDate      (active)
// 4: completionDate    (active)
// 5: lastSeenDate      (active)
// 6: effortEstimate    (active)
// 7: snoozedUntil      (active)
// 8: notifyOnWake      (active)
// 9: autoSleepSeconds  (active)
// Next available: 10

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

  @HiveField(7)
  DateTime? snoozedUntil;

  @HiveField(8)
  bool? notifyOnWake;

  @HiveField(9)
  int? autoSleepSeconds;
}
