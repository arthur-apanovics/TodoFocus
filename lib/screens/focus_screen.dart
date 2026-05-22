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
import '../theme/app_icons.dart';
import '../theme/app_palette.dart';
import 'goal_planning_screen.dart';
import 'widgets/focus_picker_sheet.dart';
import 'widgets/goal_symbol.dart';
import 'widgets/snooze_picker_sheet.dart';

/// Bottom inset for the Focus list. Wider than the shared
/// [kFabSafeBottomPadding] because the Focus tab stacks a second
/// "Pick subtasks" FAB above the "Create goal" FAB.
const double _kFocusFabSafePadding = kFabSafeBottomPadding + 64;

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
      // Bottom-LEFT secondary FAB for picking subtasks. The AppShell's
      // primary "Create goal" FAB lives on the *outer* Scaffold at the
      // default bottom-right, so the two actions occupy opposite corners
      // and don't visually fight for the same space.
      //
      // Hidden when the focus list is empty — the empty-state already
      // surfaces a centred "Pick subtasks" CTA, so a corner FAB would just
      // duplicate it.
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton:
          partition.isEmpty ? null : const _PickSubtasksFab(),
      body: partition.isEmpty
          ? const _EmptyFocusState()
          : Column(
              children: [
                // Banner is pinned to the top — it no longer scrolls away
                // with the list.
                _Banner(
                  pending: partition.pendingTotal,
                  completed: partition.completedTotal,
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
///
/// `FocusLayout.current` is intentionally excluded here: with the updated
/// compact layout offering its own inline completion button, "Single step"
/// is now visually identical to compact and shouldn't be exposed twice. The
/// enum value still exists for the widget settings, which sees all options.
class _FocusLayoutButton extends StatelessWidget {
  const _FocusLayoutButton();

  static const _focusScreenOptions = <FocusLayout>[
    FocusLayout.compact,
    FocusLayout.currentPlus2,
    FocusLayout.currentPlus4,
  ];

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<DisplayPreferences>();
    return PopupMenuButton<FocusLayout>(
      icon: const Icon(Icons.view_agenda_outlined),
      tooltip: 'Focus layout',
      onSelected: context.read<DisplayPreferences>().setFocusScreenLayout,
      itemBuilder: (_) => _focusScreenOptions
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
/// • [completed] holds cards whose every focused subtask is done — they
///   sink to the bottom so finished work never sits above live work.
/// • Groups whose front subtask is snoozed past today are excluded entirely.
class _TodayPartition {
  final List<ResolvedFocusGroup> active;
  final List<ResolvedFocusGroup> laterToday;
  final List<ResolvedFocusGroup> completed;

  const _TodayPartition({
    required this.active,
    required this.laterToday,
    required this.completed,
  });

  bool get isEmpty =>
      active.isEmpty && laterToday.isEmpty && completed.isEmpty;
  int get pendingTotal => _all.fold<int>(0, (s, g) => s + g.pendingCount);
  int get completedTotal => _all.fold<int>(0, (s, g) => s + g.completedCount);

  Iterable<ResolvedFocusGroup> get _all =>
      [...active, ...laterToday, ...completed];
}

/// Walks [groups] in the user's order, classifying each by the state of the
/// first non-completed subtask (the "front"). Goals whose front is snoozed
/// beyond end-of-today are dropped; goals whose front is snoozed earlier
/// today are sunk into [_TodayPartition.laterToday]; goals whose focused
/// subtasks are all complete sink into [_TodayPartition.completed].
_TodayPartition _partitionForToday(List<ResolvedFocusGroup> groups) {
  final now = DateTime.now();
  final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

  final active = <ResolvedFocusGroup>[];
  final laterToday = <ResolvedFocusGroup>[];
  final completed = <ResolvedFocusGroup>[];

  for (final g in groups) {
    final front = _frontSubtask(g.goal);
    // Snoozed front → the goal is on hold. Drop it if it wakes past today;
    // otherwise sink it into the "Later today" section.
    if (front != null && front.state == SubTaskState.snoozed) {
      final until = front.snoozedUntil;
      if (until == null || until.isAfter(endOfToday)) continue;
      laterToday.add(g);
      continue;
    }
    // Every focused subtask done → the card is finished; sink it so any
    // live or newly-added card always sits above it.
    if (g.subtasks.every((s) => s.state == SubTaskState.completed)) {
      completed.add(g);
      continue;
    }
    active.add(g);
  }

  // Sort the "later today" bucket by wake time ASC so the next-to-wake is
  // at the top of that section.
  laterToday.sort((a, b) {
    final aw = _frontSubtask(a.goal)!.snoozedUntil!;
    final bw = _frontSubtask(b.goal)!.snoozedUntil!;
    return aw.compareTo(bw);
  });

  return _TodayPartition(
    active: active,
    laterToday: laterToday,
    completed: completed,
  );
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
  /// Today-filtered partition rendered into the active / later-today /
  /// completed sections.
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
        // ── Active section: user-reorderable ─────────────────────────────
        if (partition.active.isNotEmpty)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              12,
              8,
              12,
              // When nothing follows, the active list owns the bottom of
              // the screen — add FAB-safe inset.
              partition.laterToday.isEmpty && partition.completed.isEmpty
                  ? _kFocusFabSafePadding
                  : 8,
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
            padding: EdgeInsets.fromLTRB(
              12,
              0,
              12,
              partition.completed.isEmpty ? _kFocusFabSafePadding : 8,
            ),
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

        // ── Completed: cards whose every focused step is done ────────────
        if (partition.completed.isNotEmpty) ...[
          if (partition.active.isNotEmpty || partition.laterToday.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              sliver: SliverToBoxAdapter(
                child: _SectionDivider(label: 'Completed'),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
                12, 0, 12, _kFocusFabSafePadding),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final resolved = partition.completed[i];
                  return Padding(
                    key: ValueKey(resolved.goal.goalId),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Opacity(
                      // Dimmed — finished work, kept only until "Clear done".
                      opacity: 0.6,
                      child: _GroupCard(resolved: resolved, dragIndex: -1),
                    ),
                  );
                },
                childCount: partition.completed.length,
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
                color: context.palette.muted,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              pending == 0
                  ? 'All done for today'
                  : pending == 1
                      ? '1 task to focus on'
                      : '$pending tasks to focus on',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
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
          const _FocusLayoutButton(),
        ],
      ),
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

  /// Builds the visible-row window for this goal's card.
  ///
  /// Returns at most `1 + layout.extraSteps` rows. The window is **anchored
  /// on the current step** (first non-completed subtask) and biased forward:
  ///
  /// 1. Add the current step, then upcoming pending steps after it, until
  ///    the window fills or the goal runs out of pending work.
  /// 2. If there's still room, backfill with completed steps that sit
  ///    immediately *before* the current step (most-recent first), so the
  ///    user gets the context "you just finished X, now Y".
  ///
  /// Compact returns nothing — its header carries the next-step summary
  /// and an inline completion button instead. If every step is done, the
  /// window shows the last N completed steps so finished cards aren't blank.
  List<SubTask> _visibleSubtasks(FocusLayout layout) {
    if (layout == FocusLayout.compact) return const [];
    final all = resolved.subtasks;
    final total = 1 + layout.extraSteps;
    if (all.isEmpty || total <= 0) return const [];

    // First non-completed subtask (current / pending / snoozed).
    final currentIdx =
        all.indexWhere((s) => s.state != SubTaskState.completed);

    if (currentIdx < 0) {
      // Everything's done — show the trailing tail of completed steps.
      return all.length <= total ? all : all.sublist(all.length - total);
    }

    // Forward pass: current + pending/snoozed steps after it.
    final window = <SubTask>[];
    for (var i = currentIdx; i < all.length && window.length < total; i++) {
      if (all[i].state == SubTaskState.completed) continue;
      window.add(all[i]);
    }

    // Backfill pass: completed steps immediately before current, most-recent
    // first. We collect in reverse, then reverse again to preserve goal
    // order when prepending — so the final window is always in sequence
    // order [oldest completed … current … pending].
    if (window.length < total) {
      final needed = total - window.length;
      final backfill = <SubTask>[];
      for (var i = currentIdx - 1; i >= 0 && backfill.length < needed; i--) {
        if (all[i].state == SubTaskState.completed) backfill.add(all[i]);
      }
      window.insertAll(0, backfill.reversed);
    }
    return window;
  }
}

/// One-line "what's next" summary shown under the header in compact layout,
/// so a collapsed card still tells the user what to do — and, when a step is
/// actually actionable, lets them complete it inline without expanding the
/// card. The trailing tick replaces what used to be the "Current step"
/// layout: tick + step text == compact, so the dedicated single-step option
/// became redundant and is hidden from the Focus tab picker.
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
      padding: const EdgeInsets.fromLTRB(14, 0, 4, 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: context.palette.muted),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: context.palette.muted),
            ),
          ),
          if (current != null)
            IconButton(
              icon: Icon(AppIcons.complete, color: context.palette.strong),
              tooltip: 'Mark complete',
              visualDensity: VisualDensity.compact,
              onPressed: () => context
                  .read<GoalService>()
                  .completeCurrentSubTask(goal.goalId),
            ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final ResolvedFocusGroup resolved;

  const _GroupHeader({required this.resolved});

  /// Opens the snooze picker for the goal's current step. Snoozing it puts
  /// the whole goal on hold (it sinks into "Later today" or drops off).
  Future<void> _snooze(BuildContext context) async {
    final result = await SnoozePickerSheet.show(context);
    if (result == null || !context.mounted) return;
    try {
      context.read<GoalService>().snoozeCurrentSubTask(
            resolved.goal.goalId,
            until: result.until,
            notify: result.notify,
          );
    } on StateError catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  /// Wakes the snoozed front step, taking the goal off hold immediately.
  void _wake(BuildContext context) {
    final front = _frontSubtask(resolved.goal);
    if (front == null) return;
    context
        .read<GoalService>()
        .wakeSubTask(resolved.goal.goalId, front.subtaskId);
  }

  @override
  Widget build(BuildContext context) {
    final goal = resolved.goal;
    // Snooze/wake toggle on the header: a live current step can be snoozed;
    // an on-hold goal can be woken. A fully-completed card shows neither.
    final hasCurrent = goal.currentSubTask != null;
    final onHold = goal.isOnHold;
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GoalPlanningScreen(goalId: goal.goalId),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 4, 10),
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
                          color: context.palette.muted,
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
                            size: 12, color: context.palette.accent),
                      ],
                      if (goal.isOnHold) ...[
                        const SizedBox(width: 8),
                        Text(
                          'on hold',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.palette.muted,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (hasCurrent)
              IconButton(
                tooltip: 'Snooze current step',
                icon: Icon(Icons.bedtime_outlined,
                    size: 22, color: context.palette.muted),
                onPressed: () => _snooze(context),
              )
            else if (onHold)
              IconButton(
                tooltip: 'Wake up — resume now',
                icon: Icon(Icons.bedtime_off_outlined,
                    size: 22, color: context.palette.accent),
                onPressed: () => _wake(context),
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
      color = context.palette.accent;
    } else if (diff <= 7) {
      label = 'due in ${diff}d';
      color = context.palette.accent;
    } else {
      final months = ['Jan','Feb','Mar','Apr','May','Jun',
                      'Jul','Aug','Sep','Oct','Nov','Dec'];
      label = '${months[dueDate.month - 1]} ${dueDate.day}';
      color = context.palette.muted;
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
                            ? context.palette.muted
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
                      ? context.palette.success
                      : isCurrent
                          ? context.palette.strong
                          : context.palette.muted,
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
        avatar: Icon(Icons.bedtime_outlined,
            size: 14, color: context.palette.muted),
        label: Text(
          'Snoozed · $label · Tap to wake now',
          style: TextStyle(fontSize: 11, color: context.palette.muted),
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

/// Small bottom-left FAB on the Focus screen. Opens the focus-picker
/// bottom sheet. The primary "Create goal" FAB is at bottom-right (on the
/// AppShell's Scaffold) — these two corners stay deliberately separate.
class _PickSubtasksFab extends StatelessWidget {
  const _PickSubtasksFab();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FloatingActionButton.small(
      heroTag: 'fab_pick_subtasks',
      tooltip: 'Pick subtasks for today',
      backgroundColor: cs.secondaryContainer,
      foregroundColor: cs.onSecondaryContainer,
      onPressed: () => FocusScreen.openPicker(context),
      child: const Icon(Icons.add_task),
    );
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
            Icon(Icons.bolt_outlined, size: 56, color: context.palette.muted),
            const SizedBox(height: 16),
            Text(
              'Nothing scheduled for today',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Tap "Pick" to choose subtasks from your goals.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.palette.muted),
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
