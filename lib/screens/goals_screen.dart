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

  void _showNewGoalSheet(BuildContext context) {
    // We capture these before the async gap (showModalBottomSheet)
    // because context can become invalid after an await
    // This is a Flutter-specific gotcha — more on this below
    final service = context.read<GoalService>();
    final decompositionService = context.read<GoalDecompositionService>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // allows sheet to grow with keyboard
      useSafeArea: true,
      builder: (_) => NewGoalSheet(
        goalService: service,
        decompositionService: decompositionService,
      ),
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

    return ListTile(
      title: Text(goal.title),
      subtitle: Text(_subtitleFor(goal)),
      leading: _StatusBadge(status: goal.status),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GoalDetailScreen(goalId: goal.goalId),
        ),
      ),
      // Swipe to delete — like a common iOS/Android pattern
      // We'll wrap in Dismissible for this
    );
  }

  // Computed display string — keeps the widget tree clean
  String _subtitleFor(Goal goal) {
    if (goal.status == GoalStatus.inbox) return 'In inbox — tap to decompose';
    if (goal.subtasks.isEmpty) return 'No subtasks yet';
    return '${goal.completedSubtaskCount} of ${goal.subtasks.length} complete';
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
