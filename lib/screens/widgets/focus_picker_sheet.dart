import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/enums.dart';
import '../../models/goal.dart';
import '../../models/sub_task.dart';
import '../../services/daily_reset_service.dart';
import '../../services/display_preferences.dart';
import '../../services/focus_list_service.dart';
import '../../services/goal_queries.dart';
import '../../services/goal_repository.dart';
import '../../theme/app_colors.dart';
import '../goal_planning_screen.dart';
import 'app_bottom_sheet.dart';
import 'goal_symbol.dart';

/// Sheet for adding subtasks to today's focus.
///
/// Each active goal is one [ExpansionTile]. Its leading bulk-star toggles
/// the "fully focused" intent for that goal. Inside, each pending subtask
/// is a checkbox row.
///
/// Selection is **sequential**: ticking subtask N also ticks every pending
/// subtask before it; unticking subtask N unticks every pending subtask
/// after it. The model enforces this in [FocusListService] — the UI just
/// forwards the tap; the cascade happens silently and the checkbox states
/// rebuild from the resulting service state.
///
/// Goals are ordered first by "has pending subtasks" (so empty goals sink
/// to the bottom regardless of sort), then by the user's selected sort
/// order from [DisplayPreferences] — same control as the Goals list, so the
/// two views stay in step. Long-pressing a goal title navigates to that
/// goal so the user can quickly add/edit subtasks before scheduling them.
class FocusPickerSheet extends StatelessWidget {
  const FocusPickerSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final queries = context.watch<GoalQueries>();
    final reset = context.watch<DailyResetService>();
    final prefs = context.watch<DisplayPreferences>();

    final sorted = _orderForPicker(queries.goals, reset, prefs.sortOrder);

    return AppBottomSheet(
      title: 'Pick subtasks for today',
      trailing: _SortMenuButton(current: prefs.sortOrder),
      children: [
        if (sorted.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
            child: Text(
              'No active goals yet — create one first.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted),
            ),
          )
        else
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: sorted.length,
              itemBuilder: (_, i) => _GoalSection(goal: sorted[i]),
            ),
          ),
      ],
    );
  }

  /// Sorts goals for the picker:
  ///   1. Goals with pending subtasks come first (no point scheduling a
  ///      goal you can't add anything from).
  ///   2. Within each bucket, the user's preferred sort order is applied
  ///      via [DailyResetService.sortGoals] — same logic as the Goals tab.
  static List<Goal> _orderForPicker(
    List<Goal> goals,
    DailyResetService reset,
    GoalSortOrder order,
  ) {
    final withPending = <Goal>[];
    final withoutPending = <Goal>[];
    for (final goal in goals) {
      final hasPending =
          goal.subtasks.any((s) => s.state == SubTaskState.pending);
      (hasPending ? withPending : withoutPending).add(goal);
    }
    return [
      ...reset.sortGoals(withPending, order),
      ...reset.sortGoals(withoutPending, order),
    ];
  }
}

/// IconButton that opens a popup menu to switch the [DisplayPreferences]
/// sort order. Mirrors the sort button on the Goals tab so the user only
/// has to learn one control.
class _SortMenuButton extends StatelessWidget {
  final GoalSortOrder current;

  const _SortMenuButton({required this.current});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<GoalSortOrder>(
      icon: const Icon(Icons.sort),
      tooltip: 'Sort goals',
      initialValue: current,
      onSelected: (v) =>
          context.read<DisplayPreferences>().setSortOrder(v),
      itemBuilder: (_) => [
        _item(GoalSortOrder.dateAdded, 'Date added', current),
        _item(GoalSortOrder.urgency, 'Urgency', current),
        _item(GoalSortOrder.smart, 'Smart', current),
      ],
    );
  }

  PopupMenuItem<GoalSortOrder> _item(
    GoalSortOrder value,
    String label,
    GoalSortOrder current,
  ) {
    return PopupMenuItem(
      value: value,
      child: ListTile(
        title: Text(label),
        trailing:
            current == value ? const Icon(Icons.check, size: 18) : null,
        contentPadding: EdgeInsets.zero,
        dense: true,
        minLeadingWidth: 0,
      ),
    );
  }
}

class _GoalSection extends StatelessWidget {
  final Goal goal;

  const _GoalSection({required this.goal});

  @override
  Widget build(BuildContext context) {
    final focus = context.watch<FocusListService>();
    final pending = goal.subtasks
        .where((s) => s.state == SubTaskState.pending)
        .toList();

    if (pending.isEmpty) {
      // Greyed out — keeps the goal discoverable (you can still tap the
      // title to navigate) but communicates there's nothing to schedule.
      return ListTile(
        leading: Icon(Icons.check_circle, color: AppColors.muted),
        title: GestureDetector(
          onLongPress: () => _openGoal(context),
          child: Text(goal.title, style: TextStyle(color: AppColors.muted)),
        ),
        subtitle: const Text('No pending subtasks'),
        dense: true,
      );
    }

    final focusedPending =
        focus.focusedPendingIds(goal.goalId, goal).toSet();
    final allFocused = focus.isGoalFullyFocused(goal.goalId) ||
        focusedPending.length == pending.length;
    final noneFocused = focusedPending.isEmpty;
    final mixed = !allFocused && !noneFocused;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: !noneFocused,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: _BulkStarButton(
          allFocused: allFocused,
          mixed: mixed,
          onTap: () {
            final f = context.read<FocusListService>();
            final repo = context.read<GoalRepository>();
            if (allFocused) {
              f.unfocusGoalFully(goal.goalId);
            } else {
              f.focusGoalFully(goal.goalId, repo);
            }
          },
        ),
        // Long-press anywhere on the header to jump into the goal screen.
        // Tap still expands/collapses (default ExpansionTile behaviour) —
        // gesture arena handles the disambiguation since long-press and tap
        // are different recognisers.
        title: GestureDetector(
          onLongPress: () => _openGoal(context),
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              if (goal.emoji != null) ...[
                GoalSymbol(name: goal.emoji, size: 18),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(goal.title, overflow: TextOverflow.ellipsis),
              ),
              Text(
                '${focusedPending.length}/${pending.length}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.muted,
                    ),
              ),
            ],
          ),
        ),
        childrenPadding: const EdgeInsets.only(bottom: 4),
        children: [
          for (var i = 0; i < pending.length; i++)
            _SequentialRow(
              goalId: goal.goalId,
              subtask: pending[i],
              positionLabel: '${i + 1}',
              isInFocus: focusedPending.contains(pending[i].subtaskId),
            ),
        ],
      ),
    );
  }

  void _openGoal(BuildContext context) {
    Navigator.of(context).pop(); // close the sheet first
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GoalPlanningScreen(goalId: goal.goalId),
      ),
    );
  }
}

class _BulkStarButton extends StatelessWidget {
  final bool allFocused;
  final bool mixed;
  final VoidCallback onTap;

  const _BulkStarButton({
    required this.allFocused,
    required this.mixed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color color;
    if (allFocused) {
      icon = Icons.star_rounded;
      color = AppColors.accent;
    } else if (mixed) {
      icon = Icons.star_half_rounded;
      color = AppColors.accent;
    } else {
      icon = Icons.star_outline_rounded;
      color = AppColors.muted;
    }
    return IconButton(
      icon: Icon(icon, color: color, size: 28),
      tooltip: allFocused
          ? 'Remove all from today\'s focus'
          : 'Add all pending to today\'s focus',
      onPressed: onTap,
    );
  }
}

/// A single pending-subtask row in the picker. Number prefix communicates
/// the sequential position so users notice the "this is step N of M" framing.
class _SequentialRow extends StatelessWidget {
  final String goalId;
  final SubTask subtask;
  final String positionLabel;
  final bool isInFocus;

  const _SequentialRow({
    required this.goalId,
    required this.subtask,
    required this.positionLabel,
    required this.isInFocus,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _toggle(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 16, 4),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                positionLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                ),
              ),
            ),
            Expanded(
              child: Text(
                subtask.description,
                style: const TextStyle(fontSize: 14),
              ),
            ),
            Checkbox(
              value: isInFocus,
              onChanged: (_) => _toggle(context),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  void _toggle(BuildContext context) {
    final f = context.read<FocusListService>();
    final repo = context.read<GoalRepository>();
    if (isInFocus) {
      f.unfocusSubtask(goalId, subtask.subtaskId, repo);
    } else {
      f.focusSubtask(goalId, subtask.subtaskId, repo);
    }
  }
}
