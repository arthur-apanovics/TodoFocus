import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import '../models/goal.dart';
import '../models/enums.dart';
import '../services/goal_queries.dart';
import '../services/goal_service.dart';
import 'goal_detail_screen.dart';

class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final queries = context.watch<GoalQueries>();
    final goals = queries.goals;

    return Scaffold(
      appBar: AppBar(title: const Text('Goals')),
      body: goals.isEmpty ? const _EmptyState() : _GoalList(goals: goals),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.flag_outlined, size: 48),
          SizedBox(height: 12),
          Text('No goals yet'),
          SizedBox(height: 4),
          Text(
            'Tap + to add your first goal',
            style: TextStyle(color: Colors.grey),
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
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            icon: Icons.delete_outline,
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
                color: goal.isFocusedToday ? Colors.indigo : Colors.grey,
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
    GoalStatus.paused => Icons.pause_circle_outline,
    GoalStatus.completed => Icons.check_circle_outline,
  };

  Color _colorFor(GoalStatus status) => switch (status) {
    GoalStatus.inbox => Colors.grey,
    GoalStatus.active => Colors.indigo,
    GoalStatus.paused => Colors.orange,
    GoalStatus.completed => Colors.green,
  };
}
