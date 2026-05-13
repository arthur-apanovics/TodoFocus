import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import '../models/goal.dart';
import '../models/enums.dart';
import '../services/goal_queries.dart';
import '../services/goal_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import 'goal_detail_screen.dart';

class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final queries = context.watch<GoalQueries>();
    final goals = queries.goals;

    return Scaffold(
      body: goals.isEmpty ? const _EmptyState() : _GoalList(goals: goals),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.flag_outlined, size: 48),
          const SizedBox(height: 12),
          const Text('No goals yet'),
          const SizedBox(height: 4),
          Text(
            'Tap + to add your first goal',
            style: TextStyle(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _GoalList extends StatelessWidget {
  final List<Goal> goals;

  const _GoalList({required this.goals});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: goals.length,
      itemBuilder: (context, index) => _GoalTile(goal: goals[index]),
    );
  }
}

class _GoalTile extends StatelessWidget {
  final Goal goal;

  const _GoalTile({required this.goal});

  @override
  Widget build(BuildContext context) {
    final service = context.read<GoalService>();

    return Slidable(
      key: ValueKey(goal.goalId),
      // Swipe left reveals the delete action; no auto-dismiss.
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
        title: Text(goal.title),
        subtitle: Text(_subtitleFor(goal)),
        leading: _StatusBadge(status: goal.status),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                goal.isFocusedToday ? Icons.star : Icons.star_border,
                color: goal.isFocusedToday
                    ? AppColors.accent
                    : AppColors.muted,
              ),
              tooltip: goal.isFocusedToday
                  ? 'Remove from Today'
                  : 'Add to Today',
              onPressed: () => service.toggleFocusToday(goal),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GoalDetailScreen(goalId: goal.goalId),
          ),
        ),
      ),
    );
  }

  String _subtitleFor(Goal goal) {
    if (goal.status == GoalStatus.inbox) return 'In inbox — tap to decompose';
    if (goal.subtasks.isEmpty) return 'No subtasks yet';
    return '${goal.completedSubtaskCount} of ${goal.subtasks.length} complete';
  }
}

class _StatusBadge extends StatelessWidget {
  final GoalStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    return Icon(_iconFor(status), color: _colorFor(status));
  }

  IconData _iconFor(GoalStatus status) => switch (status) {
    GoalStatus.inbox => Icons.inbox_outlined,
    GoalStatus.active => Icons.flag_outlined,
    GoalStatus.completed => Icons.check_circle_outline,
  };

  Color _colorFor(GoalStatus status) => switch (status) {
    GoalStatus.inbox => AppColors.muted,
    GoalStatus.active => AppColors.accent,
    GoalStatus.completed => AppColors.success,
  };
}
