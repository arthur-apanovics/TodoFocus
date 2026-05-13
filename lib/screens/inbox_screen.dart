import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import '../models/goal.dart';
import '../services/decomposition_state.dart';
import '../services/goal_queries.dart';
import '../services/goal_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import 'goal_detail_screen.dart';

// The Inbox tab — shows goals captured without any decomposition yet.
// Tapping an item navigates to the detail screen, where the user adds
// subtasks. As soon as the first subtask is added, Goal._recalculateStatus()
// flips the goal's status from `inbox` to `active`, so it leaves this list
// and shows up on the Goals tab instead.
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
          Icon(Icons.inbox_outlined, size: 48, color: AppColors.muted),
          const SizedBox(height: 12),
          const Text('Inbox is empty'),
          const SizedBox(height: 4),
          Text(
            'Capture quick ideas here to process later',
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
            : Icon(Icons.inbox_outlined, color: AppColors.muted),
        title: Text(goal.title),
        subtitle: Text(
          isDecomposing
              ? 'Generating subtasks…'
              : goal.notes.isNotEmpty
                  ? goal.notes
                  : 'Tap to add subtasks',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        // Reuse the detail screen — adding a subtask there will move
        // this goal out of the inbox automatically (see Goal.addSubTask).
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GoalDetailScreen(goalId: goal.goalId),
          ),
        ),
      ),
    );
  }
}
