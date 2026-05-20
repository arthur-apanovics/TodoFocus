import 'enums.dart';

class SubTask {
  final String subtaskId;
  String description;
  SubTaskState state;
  final DateTime assignedDate;
  DateTime? completionDate;
  DateTime lastSeenDate;
  final int? effortEstimate;

  /// When [state] is [SubTaskState.snoozed], the moment at which the
  /// subtask should auto-wake (i.e. transition back to
  /// [SubTaskState.pending]). Outside snoozed state this is null.
  DateTime? snoozedUntil;

  /// Whether the [SchedulingService] should post a wake-up notification
  /// at [snoozedUntil]. User-configured per snooze in the picker; default
  /// false to avoid surprising the user with new notifications.
  bool notifyOnWake;

  /// Pre-scheduled "go to sleep" duration that fires when this subtask
  /// **becomes the goal's current step**. Use case: a subtask like
  /// "check email 3 days later" can be flagged at planning time; when the
  /// previous step finishes, this one is automatically snoozed for the
  /// configured duration instead of immediately demanding attention.
  ///
  /// Semantics:
  ///   • Set on a queued pending subtask → fires the next time
  ///     [Goal.completeSubTask] / [Goal.completeCurrentSubTask] advances
  ///     to this step. The field is then cleared so it doesn't re-trigger
  ///     after a future un-completion / re-completion cycle.
  ///   • Set on the goal's *current* pending subtask → applied immediately
  ///     by [GoalService.setSubTaskAutoSleep] (and the field is cleared).
  ///   • Null = no auto-sleep configured (default).
  Duration? autoSleepDuration;

  SubTask({
    required this.subtaskId,
    required this.description,
    this.state = SubTaskState.pending,
    DateTime? assignedDate,
    this.completionDate,
    DateTime? lastSeenDate,
    this.effortEstimate,
    this.snoozedUntil,
    this.notifyOnWake = false,
    this.autoSleepDuration,
  })  : assignedDate = assignedDate ?? DateTime.now(),
        lastSeenDate = lastSeenDate ?? DateTime.now();

  bool get isCompleted => state == SubTaskState.completed;

  /// True when the subtask is snoozed AND its wake time has arrived.
  /// The scheduling service polls this to decide which subtasks to wake.
  bool get isReadyToWake =>
      state == SubTaskState.snoozed &&
      snoozedUntil != null &&
      !DateTime.now().isBefore(snoozedUntil!);

  void markComplete() {
    state = SubTaskState.completed;
    completionDate = DateTime.now();
    lastSeenDate = DateTime.now();
    // Clear any snooze metadata — a completed subtask can't be snoozed.
    snoozedUntil = null;
    notifyOnWake = false;
  }

  void markIncomplete() {
    state = SubTaskState.pending;
    completionDate = null;
    lastSeenDate = DateTime.now();
  }

  /// Transitions a pending subtask into [SubTaskState.snoozed] with the
  /// given wake-up time. Throws [StateError] when the subtask is already
  /// completed (no point snoozing a finished step).
  void snooze(DateTime until, {bool notify = false}) {
    if (state == SubTaskState.completed) {
      throw StateError('Cannot snooze a completed subtask.');
    }
    state = SubTaskState.snoozed;
    snoozedUntil = until;
    notifyOnWake = notify;
    lastSeenDate = DateTime.now();
  }

  /// Wakes a snoozed subtask immediately, reverting it to pending. Safe to
  /// call on a non-snoozed subtask — it's just a no-op.
  void wakeUp() {
    if (state != SubTaskState.snoozed) return;
    state = SubTaskState.pending;
    snoozedUntil = null;
    notifyOnWake = false;
    lastSeenDate = DateTime.now();
  }

  void updateDescription(String newDescription) {
    description = newDescription;
  }

  // ── Serialisation ────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'subtaskId': subtaskId,
        'description': description,
        'state': state.name,
        'assignedDate': assignedDate.toIso8601String(),
        'completionDate': completionDate?.toIso8601String(),
        'lastSeenDate': lastSeenDate.toIso8601String(),
        'effortEstimate': effortEstimate,
        if (snoozedUntil != null) 'snoozedUntil': snoozedUntil!.toIso8601String(),
        if (notifyOnWake) 'notifyOnWake': true,
        // Stored as integer seconds so the JSON stays compact and
        // round-trip-safe (Duration's toString isn't reliably parseable).
        if (autoSleepDuration != null)
          'autoSleepSeconds': autoSleepDuration!.inSeconds,
      };

  factory SubTask.fromJson(Map<String, dynamic> json) {
    final autoSleepSecs = json['autoSleepSeconds'] as int?;
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
      snoozedUntil: json['snoozedUntil'] != null
          ? DateTime.parse(json['snoozedUntil'] as String)
          : null,
      notifyOnWake: json['notifyOnWake'] as bool? ?? false,
      autoSleepDuration:
          autoSleepSecs != null ? Duration(seconds: autoSleepSecs) : null,
    );
  }
}
