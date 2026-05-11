import 'package:todo_app/models/enums.dart';

class SubTask {
  final String subtaskId;
  final String description;
  SubTaskState state; // mutable — user changes this
  final DateTime assignedDate;
  DateTime? completionDate; // nullable — not set until complete
  DateTime lastSeenDate; // mutable — updated on interaction
  final int? effortEstimate; // nullable — optional field

  SubTask({
    required this.subtaskId,
    required this.description,
    this.state = SubTaskState.pending, // default value
    DateTime? assignedDate, // nullable param, handled below
    this.completionDate,
    DateTime? lastSeenDate,
    this.effortEstimate,
  }) : assignedDate = assignedDate ?? DateTime.now(),
       lastSeenDate = lastSeenDate ?? DateTime.now();

  bool get isCompleted => state == SubTaskState.completed;

  bool get isDailyAssignable => !isCompleted;

  void markPending() {
    state = SubTaskState.pending;
    completionDate = null; // clear completion date if stepping back
    lastSeenDate = DateTime.now();
  }

  void markInProgress() {
    state = SubTaskState.inProgress;
    lastSeenDate = DateTime.now();
  }

  void markComplete() {
    state = SubTaskState.completed;
    completionDate = DateTime.now();
    lastSeenDate = DateTime.now();
  }

  // Manual serialisation — Dart's equivalent of JsonSerializer.Serialize()
  Map<String, dynamic> toJson() => {
    'subtaskId': subtaskId,
    'description': description,
    'state': state.name, // .name gives you the string "pending" etc.
    'assignedDate': assignedDate.toIso8601String(),
    'completionDate': completionDate?.toIso8601String(),
    'lastSeenDate': lastSeenDate.toIso8601String(),
    'effortEstimate': effortEstimate,
  };

  // Named constructor — like a static factory method in C#
  factory SubTask.fromJson(Map<String, dynamic> json) {
    return SubTask(
      subtaskId: json['subtaskId'] as String,
      description: json['description'] as String,
      state: SubTaskState.values.byName(json['state'] as String),
      assignedDate: DateTime.parse(json['assignedDate'] as String),
      completionDate: json['completionDate'] != null
          ? DateTime.parse(json['completionDate'] as String)
          : null,
      lastSeenDate: DateTime.parse(json['lastSeenDate'] as String),
      effortEstimate: json['effortEstimate'] as int?,
    );
  }
}
