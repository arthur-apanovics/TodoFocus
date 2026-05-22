import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/enums.dart';
import '../models/goal.dart';
import '../models/sub_task.dart';
import 'goal_repository.dart';

/// One goal's worth of focused subtasks.
///
/// **Invariants** (enforced by [FocusListService]'s mutation API — every
/// public mutator either preserves both, or no-ops):
///   1. The PENDING subtask ids in [subtaskIds] form a contiguous prefix of
///      the goal's pending-subtask sequence. Skipping ahead is forbidden
///      because subtasks complete in order — you can't usefully focus on a
///      step you're blocked from starting.
///   2. Completed subtask ids in [subtaskIds] are historical, frozen entries
///      (they were once pending and got ticked off while in focus). They are
///      preserved across reconciliations so the user keeps visual progress.
///
/// [isFullyFocused] is the sticky "I want the whole goal" intent. When true,
/// new subtasks added to the goal are auto-appended to [subtaskIds].
@immutable
class FocusGroup {
  final String goalId;
  final List<String> subtaskIds;
  final bool isFullyFocused;

  FocusGroup({
    required this.goalId,
    List<String>? subtaskIds,
    this.isFullyFocused = false,
  }) : subtaskIds = List.unmodifiable(subtaskIds ?? const []);

  FocusGroup copyWith({List<String>? subtaskIds, bool? isFullyFocused}) {
    return FocusGroup(
      goalId: goalId,
      subtaskIds: subtaskIds ?? this.subtaskIds,
      isFullyFocused: isFullyFocused ?? this.isFullyFocused,
    );
  }

  Map<String, dynamic> toJson() => {
        'g': goalId,
        's': subtaskIds,
        if (isFullyFocused) 'f': true,
      };

  factory FocusGroup.fromJson(Map<String, dynamic> json) => FocusGroup(
        goalId: json['g'] as String,
        subtaskIds: (json['s'] as List).cast<String>(),
        isFullyFocused: json['f'] as bool? ?? false,
      );
}

/// A [FocusGroup] resolved against the live repository — [subtasks] is in
/// goal.subtasks order, dropped if the goal or subtask is missing. Returned
/// by [FocusListService.resolveGroups] so screens don't repeat the lookup.
@immutable
class ResolvedFocusGroup {
  final FocusGroup group;
  final Goal goal;
  final List<SubTask> subtasks;

  const ResolvedFocusGroup({
    required this.group,
    required this.goal,
    required this.subtasks,
  });

  int get pendingCount =>
      subtasks.where((s) => s.state == SubTaskState.pending).length;
  int get completedCount =>
      subtasks.where((s) => s.state == SubTaskState.completed).length;
}

/// Owns the user's "today's focus" working set as an ordered list of
/// [FocusGroup]s — one per goal that has at least one subtask selected.
///
/// Two big invariants are enforced here rather than in the UI:
///   • Sequential selection within a goal (see [FocusGroup]).
///   • Auto-expansion when new subtasks are added to a fully-focused goal
///     (via [onSubtasksAddedToGoal], called from [GoalService]).
///
/// Persistence is a single JSON blob in the shared `app_settings` Hive box.
class FocusListService extends ChangeNotifier {
  static const _boxName = 'app_settings';
  static const _groupsKey = 'focus_list_groups_v2';

  // Null in tests — see [FocusListService.inMemory]. When null, [_persist]
  // is a no-op so the service can be exercised without spinning up Hive.
  final Box<String>? _box;
  final List<FocusGroup> _groups;

  FocusListService._({required Box<String>? box, required List<FocusGroup> groups})
      : _box = box,
        _groups = groups;

  /// Non-persistent constructor for tests. State lives only in memory.
  factory FocusListService.inMemory() =>
      FocusListService._(box: null, groups: []);

  // --- Read API ---

  List<FocusGroup> get groups => List.unmodifiable(_groups);

  bool isInFocus(String goalId, String subtaskId) {
    final g = _find(goalId);
    return g?.subtaskIds.contains(subtaskId) ?? false;
  }

  bool isGoalFullyFocused(String goalId) =>
      _find(goalId)?.isFullyFocused ?? false;

  /// True if any subtask of [goalId] is in focus, OR if the goal is fully
  /// focused (even with no subtasks selected yet — shouldn't normally happen
  /// but defensive). Used by goal-row star indicators in the goals list.
  bool hasFocus(String goalId) {
    final g = _find(goalId);
    return g != null && (g.subtaskIds.isNotEmpty || g.isFullyFocused);
  }

  /// The set of pending IDs currently focused in [goalId], in goal order.
  /// Useful for "highest-numbered focused step" UI hints.
  List<String> focusedPendingIds(String goalId, Goal goal) {
    final g = _find(goalId);
    if (g == null) return const [];
    final ids = g.subtaskIds.toSet();
    return goal.subtasks
        .where((s) =>
            s.state == SubTaskState.pending && ids.contains(s.subtaskId))
        .map((s) => s.subtaskId)
        .toList();
  }

  /// Resolves every group against the live repository, skipping dangling
  /// refs and goals that have been deleted. Subtasks within each group are
  /// returned in the goal's natural (sequential) order.
  List<ResolvedFocusGroup> resolveGroups(GoalRepository repo) {
    final result = <ResolvedFocusGroup>[];
    for (final group in _groups) {
      final goal = repo.findById(group.goalId);
      if (goal == null) continue;
      final stored = group.subtaskIds.toSet();
      final resolved = goal.subtasks.where((st) {
        final isStored = stored.contains(st.subtaskId);
        final autoIncluded =
            group.isFullyFocused && st.state == SubTaskState.pending;
        return isStored || autoIncluded;
      }).toList();
      if (resolved.isEmpty) continue;
      result.add(
          ResolvedFocusGroup(group: group, goal: goal, subtasks: resolved));
    }
    return result;
  }

  /// The very next pending subtask the user should work on, across all
  /// groups in priority order. Drives the persistent notification.
  ({Goal goal, SubTask subtask})? firstPending(GoalRepository repo) {
    for (final resolved in resolveGroups(repo)) {
      for (final st in resolved.subtasks) {
        if (st.state == SubTaskState.pending) {
          return (goal: resolved.goal, subtask: st);
        }
      }
    }
    return null;
  }

  // --- User-facing actions ---

  /// Adds [subtaskId] to focus AND every pending subtask before it in the
  /// goal's sequence (the "cascade up" half of the contiguity invariant).
  /// No-op if the target is completed — there's no reason to focus
  /// something already done.
  ///
  /// Inbox / completed / archived goals are not focusable: only active goals
  /// can have subtasks in today's plan. Trying to focus them is a no-op
  /// rather than an error because the UI sometimes calls this from a stale
  /// context (e.g. a goal just got archived in another tab). The "should be
  /// unrepresentable" invariant lives in [Goal.isDailyAssignable].
  Future<void> focusSubtask(
    String goalId,
    String subtaskId,
    GoalRepository repo,
  ) async {
    final goal = repo.findById(goalId);
    if (goal == null) return;
    if (!goal.isDailyAssignable) return;
    final targetIdx =
        goal.subtasks.indexWhere((s) => s.subtaskId == subtaskId);
    if (targetIdx < 0) return;
    if (goal.subtasks[targetIdx].state != SubTaskState.pending) return;

    final existing = _find(goalId);
    final ids = <String>{...?existing?.subtaskIds};

    // Cascade: include every pending subtask at index <= target.
    for (var i = 0; i <= targetIdx; i++) {
      final s = goal.subtasks[i];
      if (s.state == SubTaskState.pending) ids.add(s.subtaskId);
    }
    final ordered = _sortByGoalOrder(ids, goal);

    _upsert(FocusGroup(
      goalId: goalId,
      subtaskIds: ordered,
      isFullyFocused: existing?.isFullyFocused ?? false,
    ));
    await _persist();
    notifyListeners();
  }

  /// Removes [subtaskId] from focus. If the target is pending, also removes
  /// every pending subtask after it (the "cascade down" half — keeping the
  /// pending portion as a contiguous prefix). Historical completed entries
  /// are untouched. Always clears the goal's fully-focused intent because
  /// granular action overrides the bulk declaration.
  Future<void> unfocusSubtask(
    String goalId,
    String subtaskId,
    GoalRepository repo,
  ) async {
    final goal = repo.findById(goalId);
    if (goal == null) return;
    final targetIdx =
        goal.subtasks.indexWhere((s) => s.subtaskId == subtaskId);
    if (targetIdx < 0) return;

    final existing = _find(goalId);
    if (existing == null || !existing.subtaskIds.contains(subtaskId)) return;

    final targetCompleted =
        goal.subtasks[targetIdx].state == SubTaskState.completed;

    final keptIds = <String>[];
    for (final id in existing.subtaskIds) {
      final idx = goal.subtasks.indexWhere((s) => s.subtaskId == id);
      if (idx < 0) continue; // drop dangling
      final s = goal.subtasks[idx];
      if (targetCompleted) {
        // Single-row removal — every other completed/pending entry stays.
        if (id == subtaskId) continue;
        keptIds.add(id);
      } else {
        // Pending target: keep completed; drop pending at >= target index.
        if (s.state == SubTaskState.completed) {
          keptIds.add(id);
        } else if (idx < targetIdx) {
          keptIds.add(id);
        }
      }
    }

    if (keptIds.isEmpty) {
      _remove(goalId);
    } else {
      _upsert(FocusGroup(
        goalId: goalId,
        subtaskIds: keptIds,
        isFullyFocused: false,
      ));
    }
    await _persist();
    notifyListeners();
  }

  /// Sticky-focuses the whole goal: marks it fully focused, AND ensures
  /// every currently-pending subtask is in [subtaskIds]. Preserves any
  /// already-stored completed-state entries (historical).
  ///
  /// No-op for non-active goals (inbox / completed / archived) — see the
  /// [focusSubtask] docstring for the rationale.
  Future<void> focusGoalFully(String goalId, GoalRepository repo) async {
    final goal = repo.findById(goalId);
    if (goal == null) return;
    if (!goal.isDailyAssignable) return;

    final existing = _find(goalId);
    final completedHistorical = <String>[];
    if (existing != null) {
      for (final id in existing.subtaskIds) {
        final st =
            goal.subtasks.where((s) => s.subtaskId == id).firstOrNull;
        if (st != null && st.state == SubTaskState.completed) {
          completedHistorical.add(id);
        }
      }
    }
    final allIds = <String>{
      ...completedHistorical,
      ...goal.subtasks
          .where((s) => s.state == SubTaskState.pending)
          .map((s) => s.subtaskId),
    };
    final ordered = _sortByGoalOrder(allIds, goal);

    _upsert(FocusGroup(
      goalId: goalId,
      subtaskIds: ordered,
      isFullyFocused: true,
    ));
    await _persist();
    notifyListeners();
  }

  /// Removes the whole goal from focus — clears its group entirely.
  Future<void> unfocusGoalFully(String goalId) async {
    if (_find(goalId) == null) return;
    _remove(goalId);
    await _persist();
    notifyListeners();
  }

  /// Reorders the groups (the goal-level priority list). Subtasks within a
  /// goal stay locked to the goal's natural order — they're sequential, so
  /// reordering them doesn't make sense.
  Future<void> reorderGroups(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 || oldIndex >= _groups.length) return;
    final moving = _groups.removeAt(oldIndex);
    _groups.insert(newIndex.clamp(0, _groups.length), moving);
    await _persist();
    notifyListeners();
  }

  /// Drops every completed entry from every group. Groups that become empty
  /// (no completed-historicals AND no remaining pending) are removed.
  Future<void> clearCompleted(GoalRepository repo) async {
    var changed = false;
    for (var i = _groups.length - 1; i >= 0; i--) {
      final group = _groups[i];
      final goal = repo.findById(group.goalId);
      if (goal == null) continue;
      final completedIds = goal.subtasks
          .where((s) => s.state == SubTaskState.completed)
          .map((s) => s.subtaskId)
          .toSet();
      final newIds =
          group.subtaskIds.where((id) => !completedIds.contains(id)).toList();
      if (newIds.length == group.subtaskIds.length) continue;
      changed = true;
      if (newIds.isEmpty && !group.isFullyFocused) {
        _groups.removeAt(i);
      } else {
        _groups[i] = group.copyWith(subtaskIds: newIds);
      }
    }
    if (!changed) return;
    await _persist();
    notifyListeners();
  }

  Future<void> clearAll() async {
    if (_groups.isEmpty) return;
    _groups.clear();
    await _persist();
    notifyListeners();
  }

  /// Drops everything related to [goalId] — used on archive/delete/restore.
  Future<void> dropGoal(String goalId) async {
    if (!_remove(goalId)) return;
    await _persist();
    notifyListeners();
  }

  // --- Internal reconciliation (called by GoalService after mutations) ---

  /// Called by [GoalService] when new subtasks are appended to a goal.
  /// If the goal is fully focused, the new IDs auto-join the list.
  Future<void> onSubtasksAddedToGoal(
    String goalId,
    List<String> newSubtaskIds,
  ) async {
    if (newSubtaskIds.isEmpty) return;
    final group = _find(goalId);
    if (group == null || !group.isFullyFocused) return;
    final extra = newSubtaskIds.where((id) => !group.subtaskIds.contains(id));
    if (extra.isEmpty) return;
    _upsert(group.copyWith(subtaskIds: [...group.subtaskIds, ...extra]));
    await _persist();
    notifyListeners();
  }

  /// Drops a single entry without touching `isFullyFocused`. Used when a
  /// subtask is deleted upstream so dangling refs don't linger on disk.
  Future<void> removeDanglingEntry(String goalId, String subtaskId) async {
    final group = _find(goalId);
    if (group == null || !group.subtaskIds.contains(subtaskId)) return;
    final newIds = group.subtaskIds.where((id) => id != subtaskId).toList();
    if (newIds.isEmpty && !group.isFullyFocused) {
      _remove(goalId);
    } else {
      _upsert(group.copyWith(subtaskIds: newIds));
    }
    await _persist();
    notifyListeners();
  }

  /// Replaces an entry in place with [newSubtaskIds] — used by
  /// [GoalService.splitSubTask] so the position is preserved when the user
  /// breaks a focused subtask into smaller steps.
  Future<void> replaceEntry(
    String goalId,
    String oldSubtaskId,
    List<String> newSubtaskIds,
  ) async {
    final group = _find(goalId);
    if (group == null) return;
    final idx = group.subtaskIds.indexOf(oldSubtaskId);
    if (idx < 0) return;
    final replacement = newSubtaskIds.where((id) =>
        !group.subtaskIds.contains(id) || id == oldSubtaskId);
    final newIds = [...group.subtaskIds]
      ..removeAt(idx)
      ..insertAll(idx, replacement);
    _upsert(group.copyWith(subtaskIds: newIds));
    await _persist();
    notifyListeners();
  }

  /// Reconciles a goal's focus state after a bulk mutation (regenerate,
  /// modify, replace-all). Drops dangling refs; if fully focused, augments
  /// with any new pending subtask IDs.
  Future<void> reconcileAfterBulkMutation(Goal goal) async {
    final group = _find(goal.goalId);
    if (group == null) return;

    final allIds = goal.subtasks.map((s) => s.subtaskId).toSet();
    final stored = group.subtaskIds.where(allIds.contains).toList();

    final List<String> finalIds;
    if (group.isFullyFocused) {
      final storedSet = stored.toSet();
      final pending = goal.subtasks
          .where((s) => s.state == SubTaskState.pending)
          .map((s) => s.subtaskId)
          .where((id) => !storedSet.contains(id));
      finalIds =
          _sortByGoalOrder({...stored, ...pending}, goal);
    } else {
      finalIds = _sortByGoalOrder(stored.toSet(), goal);
    }

    if (finalIds.isEmpty && !group.isFullyFocused) {
      _remove(goal.goalId);
    } else {
      _upsert(group.copyWith(subtaskIds: finalIds));
    }
    await _persist();
    notifyListeners();
  }

  // --- Export / Import (for backups) ---

  List<Map<String, dynamic>> exportToJson() =>
      _groups.map((g) => g.toJson()).toList();

  Future<void> importFromJson(List<dynamic> data) async {
    _groups.clear();
    for (final raw in data) {
      if (raw is Map<String, dynamic>) {
        try {
          _groups.add(FocusGroup.fromJson(raw));
        } catch (_) {}
      }
    }
    await _persist();
    notifyListeners();
  }

  // --- Helpers ---

  FocusGroup? _find(String goalId) =>
      _groups.where((g) => g.goalId == goalId).firstOrNull;

  void _upsert(FocusGroup group) {
    final idx = _groups.indexWhere((g) => g.goalId == group.goalId);
    if (idx < 0) {
      _groups.add(group);
    } else {
      _groups[idx] = group;
    }
  }

  bool _remove(String goalId) {
    final idx = _groups.indexWhere((g) => g.goalId == goalId);
    if (idx < 0) return false;
    _groups.removeAt(idx);
    return true;
  }

  /// Sorts [ids] into the order they appear in [goal.subtasks]. IDs not
  /// present in the goal sink to the end (shouldn't normally happen).
  List<String> _sortByGoalOrder(Set<String> ids, Goal goal) {
    final order = {
      for (var i = 0; i < goal.subtasks.length; i++)
        goal.subtasks[i].subtaskId: i,
    };
    final list = ids.toList();
    list.sort((a, b) =>
        (order[a] ?? 99999).compareTo(order[b] ?? 99999));
    return list;
  }

  Future<void> _persist() async {
    final box = _box;
    if (box == null) return;
    await box.put(_groupsKey, jsonEncode(exportToJson()));
  }

  static Future<FocusListService> init() async {
    final box = await Hive.openBox<String>(_boxName);
    final groups = <FocusGroup>[];
    final raw = box.get(_groupsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        for (final r in decoded) {
          if (r is Map<String, dynamic>) {
            groups.add(FocusGroup.fromJson(r));
          }
        }
      } catch (_) {
        // Corrupted JSON — start clean.
      }
    }
    return FocusListService._(box: box, groups: groups);
  }
}
