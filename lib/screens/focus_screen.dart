import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/enums.dart';
import '../models/goal.dart';
import '../models/sub_task.dart';
import '../services/focus_list_service.dart';
import '../services/goal_repository.dart';
import '../services/goal_service.dart';
import '../theme/app_colors.dart';
import 'goal_active_screen.dart';
import 'widgets/focus_picker_sheet.dart';
import 'widgets/goal_symbol.dart';

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
    final groups = focus.resolveGroups(repo);

    return Scaffold(
      body: groups.isEmpty
          ? const _EmptyFocusState()
          : _GroupsList(groups: groups),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'focus_pick',
        onPressed: () => _openPicker(context),
        icon: const Icon(Icons.add_task),
        label: const Text('Pick'),
      ),
    );
  }

  static void _openPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const FocusPickerSheet(),
    );
  }
}

class _GroupsList extends StatelessWidget {
  final List<ResolvedFocusGroup> groups;

  const _GroupsList({required this.groups});

  @override
  Widget build(BuildContext context) {
    final pendingTotal = groups.fold<int>(0, (sum, g) => sum + g.pendingCount);
    final completedTotal =
        groups.fold<int>(0, (sum, g) => sum + g.completedCount);

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          sliver: SliverToBoxAdapter(
            child: _Banner(
              pending: pendingTotal,
              completed: completedTotal,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
          sliver: SliverReorderableList(
            itemCount: groups.length,
            proxyDecorator: _draggedCardDecorator,
            onReorder: (oldIdx, newIdx) {
              context.read<FocusListService>().reorderGroups(oldIdx, newIdx);
            },
            itemBuilder: (context, index) {
              final resolved = groups[index];
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
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GroupHeader(resolved: resolved),
          Divider(
            height: 1,
            thickness: 1,
            color: cs.outlineVariant,
          ),
          for (var i = 0; i < resolved.subtasks.length; i++) ...[
            _SubtaskRow(
              goal: goal,
              subtask: resolved.subtasks[i],
              showDivider: i < resolved.subtasks.length - 1,
            ),
          ],
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
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GoalActiveScreen(goalId: goal.goalId),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
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
                ],
              ),
            ),
            // Drag hint — purely visual; the whole card is the drag handle
            // (long-press), but a glyph helps signal "this is reorderable".
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(
                Icons.drag_indicator,
                size: 20,
                color: cs.outlineVariant,
              ),
            ),
          ],
        ),
      ),
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
    final isCurrent = goal.currentSubTask?.subtaskId == subtask.subtaskId;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  subtask.description,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 19 / 14.5,
                    fontWeight: isCurrent && !isCompleted
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: isCompleted ? AppColors.muted : null,
                    decoration:
                        isCompleted ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              // Right-aligned completion circle for one-handed reach.
              IconButton(
                tooltip: isCompleted ? 'Mark incomplete' : 'Mark complete',
                onPressed: () {
                  final svc = context.read<GoalService>();
                  if (isCompleted) {
                    svc.uncompleteSubTask(goal.goalId, subtask.subtaskId);
                  } else {
                    svc.completeSubTask(goal.goalId, subtask.subtaskId);
                  }
                },
                icon: Icon(
                  isCompleted
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked,
                  color: isCompleted ? AppColors.success : AppColors.strong,
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
              onPressed: () => FocusScreen._openPicker(context),
              icon: const Icon(Icons.add_task),
              label: const Text('Pick subtasks'),
            ),
          ],
        ),
      ),
    );
  }
}
