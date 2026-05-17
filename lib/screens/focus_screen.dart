import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/goal.dart';
import '../models/sub_task.dart';
import '../services/goal_queries.dart';
import '../services/goal_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import 'goal_active_screen.dart';

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
                );
              },
            ),
    );
  }
}

// Each goal gets a card showing current + next subtask.
//
// Visual hierarchy: the *current subtask* is the hero — the user is meant to
// glance at the card and read the one thing they need to do right now. The
// goal title is demoted to an eyebrow (uppercase, tracked, muted) — it's
// just the category the current subtask belongs to. The "Current step" and
// "Up next" subtext labels were removed: size, opacity, and the accent-
// colored circle communicate which subtask is which without needing words.
class _FocusGoalCard extends StatelessWidget {
  final Goal goal;

  const _FocusGoalCard({super.key, required this.goal});

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
            builder: (_) => GoalActiveScreen(goalId: goal.goalId),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Eyebrow row — goal title (as category) + progress badge
            Row(
              children: [
                Expanded(
                  child: Text(
                    goal.title.toUpperCase(),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 16 / 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.muted,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                // Progress badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
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
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isAllDone ? AppColors.success : AppColors.accent,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Progress bar
            LinearProgressIndicator(
              value: goal.progressPercent,
              minHeight: 3,
              borderRadius: BorderRadius.circular(4),
            ),

            const SizedBox(height: 18),

            // Collapsed state — all done
            if (isAllDone) _AllDoneRow(goal: goal),

            // Active state — current is the hero, next is a quiet peek
            if (!isAllDone) ...[
              _CurrentSubTaskRow(goal: goal),
              if (goal.nextSubTask != null) ...[
                const SizedBox(height: 14),
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

// Current subtask — the hero. 20px / medium weight, accent-colored circle.
// No "Current step" label — the size jump and the accent circle do the work.
class _CurrentSubTaskRow extends StatelessWidget {
  final Goal goal;

  const _CurrentSubTaskRow({required this.goal});

  @override
  Widget build(BuildContext context) {
    final service = context.read<GoalService>();
    final current = goal.currentSubTask!;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          icon: Icon(AppIcons.complete, color: AppColors.accent, size: 28),
          tooltip: 'Mark complete',
          onPressed: () => service.completeCurrentSubTask(goal.goalId),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              current.description,
              style: const TextStyle(
                fontSize: 20,
                height: 26 / 20,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Next subtask — dimmed peek. No "Up next" label; the 0.45 opacity says it.
// Uses the same hollow-circle glyph as the active CTA so the queued / current
// / completed shapes all rhyme — opacity, not a different icon, marks state.
class _NextSubTaskPeek extends StatelessWidget {
  final SubTask subtask;

  const _NextSubTaskPeek({required this.subtask});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.45,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(AppIcons.complete, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtask.description,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// All done state — matches the hero size of _CurrentSubTaskRow so the card
// keeps the same visual rhythm when it flips from active to complete.
class _AllDoneRow extends StatelessWidget {
  final Goal goal;

  const _AllDoneRow({required this.goal});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.check_circle, color: AppColors.success, size: 28),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            'All ${goal.subtasks.length} steps complete',
            style: TextStyle(
              fontSize: 20,
              height: 26 / 20,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.2,
              color: AppColors.success,
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
