import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/goal.dart';
import '../models/sub_task.dart';
import '../services/goal_queries.dart';
import '../services/goal_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import 'goal_detail_screen.dart';

class FocusScreen extends StatelessWidget {
  const FocusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final queries = context.watch<GoalQueries>();
    final focusedGoals = queries.todayQueue;

    return Scaffold(
      body: focusedGoals.isEmpty
          ? const _EmptyFocusState()
          : ReorderableListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: focusedGoals.length,
              // Drag handle is rendered explicitly on each card, so the
              // whole tile isn't grab-on-long-press.
              buildDefaultDragHandles: false,
              onReorder: (oldIndex, newIndex) {
                context
                    .read<GoalService>()
                    .reorderTodayQueue(focusedGoals, oldIndex, newIndex);
              },
              itemBuilder: (context, index) {
                final goal = focusedGoals[index];
                return _FocusGoalCard(
                  key: ValueKey(goal.goalId),
                  goal: goal,
                  index: index,
                );
              },
            ),
    );
  }
}

// Each goal gets a card showing current + next subtask
class _FocusGoalCard extends StatelessWidget {
  final Goal goal;
  final int index;

  const _FocusGoalCard({super.key, required this.goal, required this.index});

  @override
  Widget build(BuildContext context) {
    final isAllDone = goal.currentSubTask == null;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GoalDetailScreen(goalId: goal.goalId),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Goal header row
            Row(
              children: [
                // Drag handle — touch target for reordering the today queue.
                // ReorderableDragStartListener works only inside a
                // ReorderableListView with matching index.
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(Icons.drag_handle, color: AppColors.muted),
                  ),
                ),
                Expanded(
                  child: Text(
                    goal.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Progress badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isAllDone
                        ? AppColors.successSurface
                        : AppColors.accentSurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${goal.completedSubtaskCount}/${goal.subtasks.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isAllDone ? AppColors.success : AppColors.accent,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 4),

            // Progress bar
            LinearProgressIndicator(
              value: goal.progressPercent,
              borderRadius: BorderRadius.circular(4),
            ),

            const SizedBox(height: 16),

            // Collapsed state — all done
            if (isAllDone) _AllDoneRow(goal: goal),

            // Active state — show current + peek
            if (!isAllDone) ...[
              _CurrentSubTaskRow(goal: goal),
              if (goal.nextSubTask != null) ...[
                const SizedBox(height: 8),
                _NextSubTaskPeek(subtask: goal.nextSubTask!),
              ],
            ],
          ],
          ),
        ),
      ),
    );
  }
}

// Current subtask — prominent, with complete button
class _CurrentSubTaskRow extends StatelessWidget {
  final Goal goal;

  const _CurrentSubTaskRow({required this.goal});

  @override
  Widget build(BuildContext context) {
    final service = context.read<GoalService>();
    final current = goal.currentSubTask!;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Complete button — hollow circle, matching the Goal Detail screen.
        // Filled green check is reserved for the all-done celebration state
        // (see _AllDoneRow), so the shape distinction stays clear:
        // hollow = "tap me", filled = "settled state".
        IconButton(
          icon: Icon(AppIcons.complete, color: AppColors.accent, size: 28),
          tooltip: 'Mark complete',
          onPressed: () => service.completeCurrentSubTask(goal.goalId),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                current.description,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Next subtask — dimmed peek
class _NextSubTaskPeek extends StatelessWidget {
  final SubTask subtask;

  const _NextSubTaskPeek({required this.subtask});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.45,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Same glyph as AppIcons.complete — both represent a pending
          // subtask, just passive here (peek) rather than active (CTA).
          // Routing through AppIcons keeps the visual grammar consistent
          // if you swap the pending-shape later.
          const Icon(AppIcons.nextInQueue, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subtask.description,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// All done state — collapsed summary
class _AllDoneRow extends StatelessWidget {
  final Goal goal;

  const _AllDoneRow({required this.goal});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.check_circle, color: AppColors.success, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'All ${goal.subtasks.length} steps complete',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: AppColors.success,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// Empty state — no goals focused for today
class _EmptyFocusState extends StatelessWidget {
  const _EmptyFocusState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt_outlined, size: 48, color: AppColors.muted),
          const SizedBox(height: 12),
          const Text('Nothing scheduled for today'),
          const SizedBox(height: 4),
          Text(
            'Pick a goal to focus on from the goal tab',
            style: TextStyle(color: AppColors.muted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
