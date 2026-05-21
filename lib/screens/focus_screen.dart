import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/enums.dart';
import '../models/goal.dart';
import '../models/sub_task.dart';
import '../services/display_preferences.dart';
import '../services/focus_list_service.dart';
import '../services/goal_repository.dart';
import '../services/goal_service.dart';
import '../theme/app_colors.dart';
import 'goal_planning_screen.dart';
import 'widgets/focus_picker_sheet.dart';
import 'widgets/goal_symbol.dart';
import 'widgets/snooze_picker_sheet.dart';

/// "Today's Focus" tab.
///
/// Each goal in focus renders as a stacked card with its subtasks listed in
/// sequence beneath the goal header. Cards are reorderable (long-press
/// anywhere on the card) — that's the priority dial. Subtasks within a card
/// are NOT reorderable, because they must be completed in sequence.
///
/// Interactions:
///   • Long-press a card to drag (visual feedback: card elevates + scales)
///   • Tap a subtask's right-side circle to complete it
///   • Tap the goal header to open the goal's active screen
///   • FAB → opens the picker sheet to add/remove subtasks
class FocusScreen extends StatelessWidget {
  const FocusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<GoalRepository>();
    final focus = context.watch<FocusListService>();
    final allGroups = focus.resolveGroups(repo);

    // Today-view rules (per user feedback):
    //   1. Hide goals whose front subtask is snoozed past the end of today —
    //      they can't be completed today, so they're noise.
    //   2. Goals on-hold "later today" (front subtask snoozed but waking
    //      before midnight) sink to a separate "Later today" section,
    //      sorted by wake time ASC so the next-to-wake is at the top.
    //   3. Otherwise, preserve the user's manual ordering from
    //      FocusListService.reorderGroups.
    final partition = _partitionForToday(allGroups);

    return Scaffold(
      body: partition.isEmpty
          ? const _EmptyFocusState()
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: Row(
                    children: [
                      const _FocusLayoutButton(),
                      const Spacer(),
                      TextButton.icon(
                        icon: const Icon(Icons.add_task, size: 18),
                        label: const Text('Pick subtasks'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => FocusScreen.openPicker(context),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _GroupsList(
                    partition: partition,
                    allGroups: allGroups,
                  ),
                ),
              ],
            ),
    );
  }

  /// Opens the focus-picker bottom sheet. Public so [AppShell] can wire it
  /// to the AppBar's "Pick" action button on the Focus tab.
  static void openPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const FocusPickerSheet(),
    );
  }
}

/// Popup that switches the in-app Focus tab layout. Mirrors the Goals tab's
/// layout control, but writes the independent
/// [DisplayPreferences.focusScreenLayout] — the Focus tab, the home-screen
/// widget and the Goals list each remember their own density.
class _FocusLayoutButton extends StatelessWidget {
  const _FocusLayoutButton();

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<DisplayPreferences>();
    return PopupMenuButton<FocusLayout>(
      icon: const Icon(Icons.view_agenda_outlined),
      tooltip: 'Focus layout',
      onSelected: context.read<DisplayPreferences>().setFocusScreenLayout,
      itemBuilder: (_) => FocusLayout.values
          .map(
            (v) => PopupMenuItem(
              value: v,
              child: ListTile(
                title: Text(v.displayName),
                trailing: prefs.focusScreenLayout == v
                    ? const Icon(Icons.check, size: 18)
                    : null,
                contentPadding: EdgeInsets.zero,
                dense: true,
                minLeadingWidth: 24,
              ),
            ),
          )
          .toList(),
    );
  }
}

/// Result of partitioning the focus list for the today view.
///
/// • [active] preserves user-defined order and is rendered as the
///   primary reorderable list at the top.
/// • [laterToday] is sorted by wake time ASC and rendered as a
///   non-reorderable "Later today" section below.
/// • Groups whose front subtask is snoozed past today are excluded entirely.
class _TodayPartition {
  final List<ResolvedFocusGroup> active;
  final List<ResolvedFocusGroup> laterToday;

  const _TodayPartition({required this.active, required this.laterToday});

  bool get isEmpty => active.isEmpty && laterToday.isEmpty;
  int get pendingTotal =>
      active.fold<int>(0, (s, g) => s + g.pendingCount) +
      laterToday.fold<int>(0, (s, g) => s + g.pendingCount);
  int get completedTotal =>
      active.fold<int>(0, (s, g) => s + g.completedCount) +
      laterToday.fold<int>(0, (s, g) => s + g.completedCount);
}

/// Walks [groups] in the user's order, classifying each by the state of the
/// first non-completed subtask (the "front"). Goals whose front is snoozed
/// beyond end-of-today are dropped; goals whose front is snoozed earlier
/// today are sunk into [_TodayPartition.laterToday].
_TodayPartition _partitionForToday(List<ResolvedFocusGroup> groups) {
  final now = DateTime.now();
  final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

  final active = <ResolvedFocusGroup>[];
  final laterToday = <ResolvedFocusGroup>[];

  for (final g in groups) {
    final front = _frontSubtask(g.goal);
    if (front == null) {
      // Goal has no non-completed subtask (e.g. fully focused but all done).
      // Still show it in the active list so the user can clear it.
      active.add(g);
      continue;
    }
    if (front.state != SubTaskState.snoozed) {
      active.add(g);
      continue;
    }
    final until = front.snoozedUntil;
    if (until == null || until.isAfter(endOfToday)) {
      // Snoozed indefinitely or past today — drop.
      continue;
    }
    laterToday.add(g);
  }

  // Sort the "later today" bucket by wake time ASC so the next-to-wake is
  // at the top of that section.
  laterToday.sort((a, b) {
    final aw = _frontSubtask(a.goal)!.snoozedUntil!;
    final bw = _frontSubtask(b.goal)!.snoozedUntil!;
    return aw.compareTo(bw);
  });

  return _TodayPartition(active: active, laterToday: laterToday);
}

/// First non-completed subtask of [goal]. The "front" determines whether the
/// goal is actionable, blocked by a snooze, or done. Returns null when every
/// subtask is completed.
SubTask? _frontSubtask(Goal goal) {
  for (final st in goal.subtasks) {
    if (st.state != SubTaskState.completed) return st;
  }
  return null;
}

class _GroupsList extends StatelessWidget {
  /// Today-filtered partition rendered into the two sections.
  final _TodayPartition partition;

  /// The original (unfiltered) focus list. Needed because
  /// [FocusListService.reorderGroups] operates on indices into the full
  /// list — when only a subset is visible, we have to map between
  /// "visible active index" and "full focus-list index".
  final List<ResolvedFocusGroup> allGroups;

  const _GroupsList({required this.partition, required this.allGroups});

  @override
  Widget build(BuildContext context) {
    // Precompute full-list indices of the active section so onReorder can
    // map back. activeFullIndices[i] = position in `allGroups` (== position
    // in FocusListService._groups) of partition.active[i].
    final activeFullIndices = <int>[];
    final activeIds = {for (final g in partition.active) g.goal.goalId};
    for (var i = 0; i < allGroups.length; i++) {
      if (activeIds.contains(allGroups[i].goal.goalId)) {
        activeFullIndices.add(i);
      }
    }

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          sliver: SliverToBoxAdapter(
            child: _Banner(
              pending: partition.pendingTotal,
              completed: partition.completedTotal,
            ),
          ),
        ),

        // ── Active section: user-reorderable ─────────────────────────────
        if (partition.active.isNotEmpty)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              12,
              4,
              12,
              // When there's no "later today" section below us, the active
              // list owns the bottom of the screen — add FAB-safe inset.
              partition.laterToday.isEmpty ? kFabSafeBottomPadding : 8,
            ),
            sliver: SliverReorderableList(
              itemCount: partition.active.length,
              proxyDecorator: _draggedCardDecorator,
              onReorder: (oldIdx, newIdx) {
                final oldFull = activeFullIndices[oldIdx];
                // SliverReorderableList convention: newIdx is the position
                // in the original list before the moved item is removed.
                // We map "newIdx in active section" to the equivalent
                // position in the full focus list. When dropping past the
                // last active item, we place the moving group at the
                // boundary just before the laterToday section.
                final int newFull;
                if (newIdx < activeFullIndices.length) {
                  newFull = activeFullIndices[newIdx];
                } else {
                  newFull = activeFullIndices.last + 1;
                }
                context
                    .read<FocusListService>()
                    .reorderGroups(oldFull, newFull);
              },
              itemBuilder: (context, index) {
                final resolved = partition.active[index];
                return ReorderableDelayedDragStartListener(
                  key: ValueKey(resolved.goal.goalId),
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: _GroupCard(resolved: resolved, dragIndex: index),
                  ),
                );
              },
            ),
          ),

        // ── Later today: snoozed groups waking before midnight ───────────
        if (partition.laterToday.isNotEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            sliver: SliverToBoxAdapter(
              child: _SectionDivider(label: 'Later today'),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
                12, 0, 12, kFabSafeBottomPadding),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final resolved = partition.laterToday[i];
                  return Padding(
                    key: ValueKey(resolved.goal.goalId),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Opacity(
                      // Slight dim cue to communicate "not actionable yet".
                      opacity: 0.7,
                      child: _GroupCard(resolved: resolved, dragIndex: -1),
                    ),
                  );
                },
                childCount: partition.laterToday.length,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Wraps the dragged card with elevation + a slight scale-up so it's
  /// obviously "lifted" from the list — fixes the user's complaint that
  /// dragged items looked identical to stationary ones. Hooks into the
  /// `animation` controller that [ReorderableList] drives during the lift
  /// in/out so the feedback fades naturally.
  static Widget _draggedCardDecorator(
    Widget child,
    int index,
    Animation<double> animation,
  ) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, c) {
        final t = Curves.easeInOut.transform(animation.value);
        final elevation = lerpDouble(0, 12, t)!;
        final scale = lerpDouble(1.0, 1.03, t)!;
        return Transform.scale(
          scale: scale,
          child: Material(
            elevation: elevation,
            color: Colors.transparent,
            shadowColor: Colors.black.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(14),
            child: c,
          ),
        );
      },
      child: child,
    );
  }
}

/// Slim labelled separator used between focus sections (e.g. "Later today").
class _SectionDivider extends StatelessWidget {
  final String label;
  const _SectionDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.muted,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Divider(
            color: Theme.of(context).colorScheme.outlineVariant,
            thickness: 1,
            height: 1,
          ),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  final int pending;
  final int completed;

  const _Banner({required this.pending, required this.completed});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          pending == 0
              ? 'All done for today'
              : pending == 1
                  ? '1 task to focus on'
                  : '$pending tasks to focus on',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const Spacer(),
        if (completed > 0)
          TextButton(
            onPressed: () => context
                .read<FocusListService>()
                .clearCompleted(context.read<GoalRepository>()),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            child: Text('Clear $completed done'),
          ),
      ],
    );
  }
}

/// A single goal card containing a header + a sequenced list of subtasks.
/// The card itself is the drag target; subtasks inside are not draggable.
class _GroupCard extends StatelessWidget {
  final ResolvedFocusGroup resolved;
  final int dragIndex;

  const _GroupCard({required this.resolved, required this.dragIndex});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final goal = resolved.goal;
    final layout = context.watch<DisplayPreferences>().focusScreenLayout;
    final visible = _visibleSubtasks(layout);
    return Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GroupHeader(resolved: resolved),
          if (layout == FocusLayout.compact)
            _CompactNextLine(goal: goal)
          else if (visible.isNotEmpty) ...[
            Divider(
              height: 1,
              thickness: 1,
              color: cs.outlineVariant,
            ),
            for (var i = 0; i < visible.length; i++)
              _SubtaskRow(
                goal: goal,
                subtask: visible[i],
                showDivider: i < visible.length - 1,
              ),
          ],
        ],
      ),
    );
  }

  /// Focused subtasks limited to the chosen [layout]: every completed step
  /// (frozen progress) stays visible, followed by the current step and up to
  /// N upcoming pending steps. Compact returns nothing — the header carries
  /// a one-line summary instead.
  List<SubTask> _visibleSubtasks(FocusLayout layout) {
    if (layout == FocusLayout.compact) return const [];
    final all = resolved.subtasks;
    final completed =
        all.where((s) => s.state == SubTaskState.completed).toList();
    final upcoming =
        all.where((s) => s.state != SubTaskState.completed).toList();
    return [...completed, ...upcoming.take(1 + layout.extraSteps)];
  }
}

/// One-line "what's next" summary shown under the header in compact layout,
/// so a collapsed card still tells the user what to do.
class _CompactNextLine extends StatelessWidget {
  final Goal goal;

  const _CompactNextLine({required this.goal});

  @override
  Widget build(BuildContext context) {
    final current = goal.currentSubTask;
    final String label;
    final IconData icon;
    if (current != null) {
      label = current.description;
      icon = Icons.arrow_right;
    } else if (goal.isOnHold) {
      label = 'On hold — snoozed';
      icon = Icons.bedtime_outlined;
    } else {
      label = 'All steps complete';
      icon = Icons.check_circle_outline;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.muted),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final ResolvedFocusGroup resolved;

  const _GroupHeader({required this.resolved});

  @override
  Widget build(BuildContext context) {
    final goal = resolved.goal;
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GoalPlanningScreen(goalId: goal.goalId),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Row(
          children: [
            if (goal.emoji != null) ...[
              GoalSymbol(name: goal.emoji, size: 20),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    goal.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 20 / 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        resolved.group.isFullyFocused
                            ? '${resolved.completedCount}/${resolved.subtasks.length} · whole goal'
                            : '${resolved.completedCount}/${resolved.subtasks.length} steps',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.muted,
                          letterSpacing: 0.3,
                        ),
                      ),
                      if (goal.dueDate != null) ...[
                        const SizedBox(width: 8),
                        _DueDateChip(dueDate: goal.dueDate!),
                      ],
                      // Recurrence + on-hold indicators sit beside the step
                      // counter so the user sees the goal's *state* at a
                      // glance without scrolling the subtask list.
                      if (goal.isRecurring) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.repeat,
                            size: 12, color: AppColors.accent),
                      ],
                      if (goal.isOnHold) ...[
                        const SizedBox(width: 8),
                        Text(
                          'on hold',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.muted,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact due-date label with urgency colouring.
class _DueDateChip extends StatelessWidget {
  final DateTime dueDate;

  const _DueDateChip({required this.dueDate});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final diff = d.difference(today).inDays;

    final String label;
    final Color color;
    if (diff < 0) {
      label = '${diff.abs()}d overdue';
      color = Theme.of(context).colorScheme.error;
    } else if (diff == 0) {
      label = 'due today';
      color = Theme.of(context).colorScheme.error;
    } else if (diff == 1) {
      label = 'due tomorrow';
      color = AppColors.accent;
    } else if (diff <= 7) {
      label = 'due in ${diff}d';
      color = AppColors.accent;
    } else {
      final months = ['Jan','Feb','Mar','Apr','May','Jun',
                      'Jul','Aug','Sep','Oct','Nov','Dec'];
      label = '${months[dueDate.month - 1]} ${dueDate.day}';
      color = AppColors.muted;
    }

    return Text(
      label,
      style: TextStyle(fontSize: 11, color: color, letterSpacing: 0.3),
    );
  }
}

class _SubtaskRow extends StatelessWidget {
  final Goal goal;
  final SubTask subtask;
  final bool showDivider;

  const _SubtaskRow({
    required this.goal,
    required this.subtask,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isCompleted = subtask.state == SubTaskState.completed;
    final isSnoozed = subtask.state == SubTaskState.snoozed;
    final isCurrent = goal.currentSubTask?.subtaskId == subtask.subtaskId;
    // Completion is sequential: only the first-pending subtask may be ticked.
    // Completed subtasks can always be un-ticked.
    final canInteract = isCompleted || isCurrent;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subtask.description,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 19 / 14.5,
                        fontWeight: isCurrent && !isCompleted
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: isCompleted || !isCurrent
                            ? AppColors.muted
                            : null,
                        decoration:
                            isCompleted ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    // Snooze chip — only on the snoozed row. Tap to either
                    // reschedule or wake-up immediately.
                    if (isSnoozed)
                      _SnoozeChip(
                        goalId: goal.goalId,
                        subtask: subtask,
                      ),
                  ],
                ),
              ),
              // Snooze button — only on the current step. Tucked in beside
              // the completion circle so it shares the same touch zone.
              if (isCurrent)
                IconButton(
                  tooltip: 'Snooze this step',
                  icon: Icon(
                    Icons.bedtime_outlined,
                    size: 22,
                    color: AppColors.muted,
                  ),
                  onPressed: () => _openSnoozePicker(context),
                ),
              // Completion circle (always on the right edge).
              IconButton(
                tooltip: isCompleted
                    ? 'Mark incomplete'
                    : isCurrent
                        ? 'Mark complete'
                        : isSnoozed
                            ? 'Snoozed — wakes later'
                            : 'Complete previous steps first',
                onPressed: canInteract
                    ? () {
                        final svc = context.read<GoalService>();
                        if (isCompleted) {
                          svc.uncompleteSubTask(goal.goalId, subtask.subtaskId);
                        } else {
                          svc.completeSubTask(goal.goalId, subtask.subtaskId);
                        }
                      }
                    : null,
                icon: Icon(
                  isCompleted
                      ? Icons.check_circle_rounded
                      : isCurrent
                          ? Icons.radio_button_unchecked
                          : isSnoozed
                              ? Icons.bedtime_rounded
                              : Icons.lock_outline_rounded,
                  color: isCompleted
                      ? AppColors.success
                      : isCurrent
                          ? AppColors.strong
                          : AppColors.muted,
                  size: 24,
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 12),
            child: Divider(
              height: 1,
              thickness: 1,
              color: cs.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
      ],
    );
  }

  Future<void> _openSnoozePicker(BuildContext context) async {
    final result = await SnoozePickerSheet.show(context);
    if (result == null || !context.mounted) return;
    try {
      context.read<GoalService>().snoozeCurrentSubTask(
            goal.goalId,
            until: result.until,
            notify: result.notify,
          );
    } on StateError catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }
}

/// Small inline chip on a snoozed subtask row showing the wake-up time,
/// with a tap-to-wake-now affordance.
class _SnoozeChip extends StatelessWidget {
  final String goalId;
  final SubTask subtask;

  const _SnoozeChip({required this.goalId, required this.subtask});

  @override
  Widget build(BuildContext context) {
    final until = subtask.snoozedUntil;
    final label = until != null ? _wakeLabel(until) : 'Snoozed';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: ActionChip(
        avatar: Icon(Icons.bedtime_outlined, size: 14, color: AppColors.muted),
        label: Text(
          'Snoozed · $label · Tap to wake now',
          style: TextStyle(fontSize: 11, color: AppColors.muted),
        ),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onPressed: () =>
            context.read<GoalService>().wakeSubTask(goalId, subtask.subtaskId),
      ),
    );
  }

  /// "wakes today 14:30", "wakes tomorrow 09:00", "wakes Wed 14 May 09:00"
  static String _wakeLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dt.year, dt.month, dt.day);
    final diff = target.difference(today).inDays;
    final hhmm =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (diff == 0) return 'wakes at $hhmm';
    if (diff == 1) return 'wakes tomorrow $hhmm';
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return 'wakes ${days[dt.weekday - 1]} ${dt.day} ${months[dt.month - 1]} $hhmm';
  }
}

class _EmptyFocusState extends StatelessWidget {
  const _EmptyFocusState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt_outlined, size: 56, color: AppColors.muted),
            const SizedBox(height: 16),
            Text(
              'Nothing scheduled for today',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Tap "Pick" to choose subtasks from your goals.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => FocusScreen.openPicker(context),
              icon: const Icon(Icons.add_task),
              label: const Text('Pick subtasks'),
            ),
          ],
        ),
      ),
    );
  }
}
