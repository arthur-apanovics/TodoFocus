import 'package:flutter/foundation.dart';
import '../models/enums.dart';
import '../models/goal.dart';
import '../models/recurrence.dart';
import '../models/sub_task.dart';
import 'goal_repository.dart';

/// Result of a [SchedulingService.checkAndProcess] sweep, exposed so the UI
/// (or callers like `main.dart`) can react — e.g. post a wake notification
/// or show a snackbar after a recurring goal cycles.
@immutable
class SchedulingTick {
  /// Subtasks whose snooze elapsed and were transitioned back to pending.
  /// Includes the parent [Goal] so callers can reference its title/emoji
  /// without re-querying the repository.
  final List<({Goal goal, SubTask subtask})> wokenSubtasks;

  /// Goals whose recurrence reset their subtasks in this tick.
  final List<Goal> resetGoals;

  const SchedulingTick({
    required this.wokenSubtasks,
    required this.resetGoals,
  });

  bool get isEmpty => wokenSubtasks.isEmpty && resetGoals.isEmpty;
}

/// Owns time-driven goal transitions:
///
/// 1. **Snooze wake-up** — when [SubTask.snoozedUntil] has passed, the
///    subtask flips back to [SubTaskState.pending] and its parent goal's
///    [Goal.lastResumedAt] is bumped so the sort surfaces it.
///
/// 2. **Recurrence reset** — when [Goal.nextOccurrenceAt] arrives, all the
///    goal's subtasks are flipped back to pending via
///    [Goal.resetRecurrenceCycle], the previous cycle is captured in
///    [Goal.lastIterationSummary], and the next occurrence is precomputed.
///
/// The service is *event-triggered*, not timer-based: callers invoke
/// [checkAndProcess] on app start, on resume, and after [DailyResetService]
/// runs its own check. That keeps battery use at zero and avoids the
/// awkward "what if the user is offline" timer-cancellation edge cases.
///
/// Callers that need realtime wake notifications schedule them separately
/// via [NotificationService] when the snooze is set up — the service here
/// only handles the *eventual* transition; the notification is a fire-once
/// reminder that fires on its own schedule.
class SchedulingService extends ChangeNotifier {
  final GoalRepository _repository;

  SchedulingService(this._repository);

  /// Walks every goal in the repository and applies any time-elapsed
  /// transitions. Returns a [SchedulingTick] describing what changed so
  /// callers can react (e.g. post wake notifications).
  ///
  /// Idempotent: calling it twice in a row with no time elapsed in between
  /// is a no-op the second time.
  SchedulingTick checkAndProcess({DateTime? now}) {
    final clock = now ?? DateTime.now();
    final woken = <({Goal goal, SubTask subtask})>[];
    final reset = <Goal>[];

    for (final goal in _repository.all) {
      var goalChanged = false;

      // ── 1. Wake elapsed snoozes ────────────────────────────────────────
      for (final st in goal.subtasks) {
        if (st.state != SubTaskState.snoozed) continue;
        final until = st.snoozedUntil;
        if (until == null || clock.isBefore(until)) continue;
        st.wakeUp();
        goal.lastResumedAt = clock;
        woken.add((goal: goal, subtask: st));
        goalChanged = true;
      }

      // ── 2. Recurrence resets ──────────────────────────────────────────
      // Only fire when the recurrence is configured AND the time has come.
      // We snapshot the previous lastResumedAt so we don't lose it if the
      // goal was already mid-resume from a wake event above.
      final next = goal.nextOccurrenceAt;
      if (goal.recurrence != null &&
          next != null &&
          !clock.isBefore(next)) {
        goal.resetRecurrenceCycle(now: clock);
        reset.add(goal);
        goalChanged = true;
      }

      if (goalChanged) {
        _repository.save(goal);
      }
    }

    final tick = SchedulingTick(wokenSubtasks: woken, resetGoals: reset);
    if (!tick.isEmpty) notifyListeners();
    return tick;
  }

  /// Sets up a recurrence schedule for a goal and persists the precomputed
  /// next-occurrence timestamp. Pass `null` to clear the schedule.
  ///
  /// [referenceTime] anchors the calculation of when the *first* occurrence
  /// fires — defaults to now. Useful when callers want to align all new
  /// daily-recurring goals to the same "morning" boundary.
  void configureRecurrence(
    Goal goal, {
    required Recurrence? recurrence,
    DateTime? referenceTime,
  }) {
    final ref = referenceTime ?? DateTime.now();
    goal.recurrence = recurrence;
    goal.nextOccurrenceAt = recurrence?.nextOccurrenceAfter(ref);
    _repository.save(goal);
    notifyListeners();
  }
}
