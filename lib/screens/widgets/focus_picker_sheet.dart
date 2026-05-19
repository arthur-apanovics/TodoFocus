import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/enums.dart';
import '../../models/goal.dart';
import '../../models/sub_task.dart';
import '../../services/focus_list_service.dart';
import '../../services/goal_queries.dart';
import '../../services/goal_repository.dart';
import '../../theme/app_colors.dart';
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
class FocusPickerSheet extends StatelessWidget {
  const FocusPickerSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final queries = context.watch<GoalQueries>();
    final goals = queries.goals;
    return AppBottomSheet(
      title: 'Pick subtasks for today',
      children: [
        if (goals.isEmpty)
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
              itemCount: goals.length,
              itemBuilder: (_, i) => _GoalSection(goal: goals[i]),
            ),
          ),
      ],
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
      return ListTile(
        leading: Icon(Icons.check_circle, color: AppColors.muted),
        title: Text(goal.title, style: TextStyle(color: AppColors.muted)),
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
        title: Row(
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
      onTap: () {
        final f = context.read<FocusListService>();
        final repo = context.read<GoalRepository>();
        if (isInFocus) {
          f.unfocusSubtask(goalId, subtask.subtaskId, repo);
        } else {
          f.focusSubtask(goalId, subtask.subtaskId, repo);
        }
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 16, 4),
        child: Row(
          children: [
            // Step-number bubble — communicates the sequence visually.
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
              onChanged: (_) {
                final f = context.read<FocusListService>();
                final repo = context.read<GoalRepository>();
                if (isInFocus) {
                  f.unfocusSubtask(goalId, subtask.subtaskId, repo);
                } else {
                  f.focusSubtask(goalId, subtask.subtaskId, repo);
                }
              },
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}
