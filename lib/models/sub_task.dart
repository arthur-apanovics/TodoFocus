import 'enums.dart';

class SubTask {
  final String subtaskId;
  String description;
  SubTaskState state;
  final DateTime assignedDate;
  DateTime? completionDate;
  DateTime lastSeenDate;
  final int? effortEstimate;

  SubTask({
    required this.subtaskId,
    required this.description,
    this.state = SubTaskState.pending,
    DateTime? assignedDate,
    this.completionDate,
    DateTime? lastSeenDate,
    this.effortEstimate,
  }) : assignedDate = assignedDate ?? DateTime.now(),
       lastSeenDate = lastSeenDate ?? DateTime.now();

  bool get isCompleted => state == SubTaskState.completed;

  void markComplete() {
    state = SubTaskState.completed;
    completionDate = DateTime.now();
    lastSeenDate = DateTime.now();
  }

  void markIncomplete() {
    state = SubTaskState.pending;
    completionDate = null;
    lastSeenDate = DateTime.now();
  }

  void updateDescription(String newDescription) {
    description = newDescription;
  }

  Map<String, dynamic> toJson() => {
    'subtaskId': subtaskId,
    'description': description,
    'state': state.name,
    'assignedDate': assignedDate.toIso8601String(),
    'completionDate': completionDate?.toIso8601String(),
    'lastSeenDate': lastSeenDate.toIso8601String(),
    'effortEstimate': effortEstimate,
  };

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
