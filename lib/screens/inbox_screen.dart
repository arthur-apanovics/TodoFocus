import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import '../models/goal.dart';
import '../services/decomposition_state.dart';
import '../services/goal_queries.dart';
import '../services/goal_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import 'goal_planning_screen.dart';

// The Planning tab — shows inbox goals that the user is still shaping
// into a plan. Tapping opens the planning screen where subtasks can be
// generated/added/edited and then queued for execution. Goals only leave
// this list when the user explicitly hits "Queue Goal" on the planning
// screen (or deletes the goal).
class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // watch() makes this widget rebuild when the repository notifies listeners
    // (e.g. when a goal is added to the inbox, deleted, or promoted to active).
    final queries = context.watch<GoalQueries>();
    final items = queries.inbox;

    return Scaffold(
      body: items.isEmpty ? const _EmptyState() : _InboxList(items: items),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    // AppColors fields are `final`, not `const`, so the outer Center can't
    // be const anymore — but the inner const literals stay const.
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.edit_note_outlined, size: 48, color: AppColors.muted),
          const SizedBox(height: 12),
          const Text('Nothing being planned'),
          const SizedBox(height: 4),
          Text(
            'Capture an idea and shape it here before queuing it up',
            style: TextStyle(color: AppColors.muted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _InboxList extends StatelessWidget {
  final List<Goal> items;

  const _InboxList({required this.items});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) => _InboxTile(goal: items[index]),
    );
  }
}

class _InboxTile extends StatelessWidget {
  final Goal goal;

  const _InboxTile({required this.goal});

  @override
  Widget build(BuildContext context) {
    final service = context.read<GoalService>();
    final isDecomposing =
        context.watch<DecompositionState>().isDecomposing(goal.goalId);

    return Slidable(
      key: ValueKey(goal.goalId),
      endActionPane: ActionPane(
        motion: const BehindMotion(),
        extentRatio: 0.25,
        children: [
          SlidableAction(
            onPressed: (_) => service.removeGoal(goal.goalId),
            backgroundColor: AppColors.destructive,
            foregroundColor: AppColors.onDestructive,
            icon: AppIcons.delete,
            label: 'Delete',
          ),
        ],
      ),
      child: ListTile(
        leading: isDecomposing
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(Icons.edit_note_outlined, color: AppColors.muted),
        title: Text(goal.title),
        subtitle: Text(
          isDecomposing
              ? 'Generating subtasks…'
              : goal.subtasks.isNotEmpty
                  ? '${goal.subtasks.length} subtask${goal.subtasks.length == 1 ? '' : 's'} planned'
                  : goal.notes.isNotEmpty
                      ? goal.notes
                      : 'Tap to plan this goal',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GoalPlanningScreen(goalId: goal.goalId),
          ),
        ),
      ),
    );
  }
}
