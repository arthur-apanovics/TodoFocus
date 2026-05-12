import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/goal.dart';
import '../models/enums.dart';
import '../services/goal_queries.dart';
import '../services/goal_service.dart';
import '../services/goal_decomposition_service.dart';
import 'goal_detail_screen.dart';
import 'widgets/new_goal_sheet.dart';

class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // context.watch — reactive, rebuilds this widget when repository changes
    // Like useSelector in Redux or consuming a React context that holds state
    final queries = context.watch<GoalQueries>();
    final goals = queries.all;

    return Scaffold(
      appBar: AppBar(title: const Text('Goals')),
      body: goals.isEmpty ? _EmptyState() : _GoalList(goals: goals),
    );
  }
}

// Extracted to a private widget — keeps build() readable
// Leading underscore = private to this file, not instantiable from outside
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min, // don't expand, just wrap content
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
      itemBuilder: (context, index) {
        final goal = goals[index];
        return _GoalTile(goal: goal);
      },
    );
  }
}

class _GoalTile extends StatelessWidget {
  final Goal goal;

  const _GoalTile({required this.goal});

  @override
  Widget build(BuildContext context) {
    final service = context.read<GoalService>();

    return Dismissible(
      key: ValueKey(goal.goalId),
      // Swipe right — add to / remove from focus
      secondaryBackground: _SwipeBackground(
        alignment: Alignment.centerLeft,
        color: Colors.indigo,
        icon: goal.isFocusedToday ? Icons.star_outline : Icons.star,
        label: goal.isFocusedToday ? 'Remove from Today' : 'Focus Today',
      ),
      // Swipe left — delete
      background: _SwipeBackground(
        alignment: Alignment.centerRight,
        color: Colors.red,
        icon: Icons.delete_outline,
        label: 'Delete',
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          // Swipe right = delete — confirm first
          return await _confirmDelete(context, service);
        } else {
          // Swipe left = toggle focus — no confirmation needed
          service.toggleFocusToday(goal.goalId);
          return false; // return false = don't actually dismiss the tile
        }
      },
      onDismissed: (_) => service.removeGoal(goal.goalId),
      child: ListTile(
        title: Text(goal.title),
        subtitle: Text(_subtitleFor(goal)),
        leading: _StatusBadge(status: goal.status),
        // Show focus indicator if selected for today
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (goal.isFocusedToday)
              const Icon(Icons.star, color: Colors.indigo, size: 18),
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

  Future<bool> _confirmDelete(BuildContext context, GoalService service) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete goal?'),
        content: const Text('This will delete the goal and all its subtasks.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  String _subtitleFor(Goal goal) {
    if (goal.status == GoalStatus.inbox) return 'In inbox — tap to decompose';
    if (goal.subtasks.isEmpty) return 'No subtasks yet';
    return '${goal.completedSubtaskCount} of ${goal.subtasks.length} complete';
  }
}

// Reusable swipe background — used for both directions
class _SwipeBackground extends StatelessWidget {
  final Alignment alignment;
  final Color color;
  final IconData icon;
  final String label;

  const _SwipeBackground({
    required this.alignment,
    required this.color,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// Small self-contained widget for the status indicator
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
