import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import '../models/goal.dart';
import '../models/enums.dart';
import '../services/daily_reset_service.dart';
import '../services/decomposition_state.dart';
import '../services/goal_queries.dart';
import '../services/goal_service.dart';
import '../theme/app_colors.dart';
import 'goal_detail_screen.dart';

enum _GoalFilter { active, completed }

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  _GoalFilter _filter = _GoalFilter.active;

  @override
  Widget build(BuildContext context) {
    final queries = context.watch<GoalQueries>();
    final resetService = context.watch<DailyResetService>();

    final goals = _filter == _GoalFilter.active
        ? resetService.sortGoals(queries.goals, resetService.sortOrder)
        : queries.completedGoals;

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SegmentedButton<_GoalFilter>(
              segments: const [
                ButtonSegment(
                  value: _GoalFilter.active,
                  label: Text('Active'),
                  icon: Icon(Icons.flag_outlined),
                ),
                ButtonSegment(
                  value: _GoalFilter.completed,
                  label: Text('Completed'),
                  icon: Icon(Icons.check_circle_outline),
                ),
              ],
              selected: {_filter},
              onSelectionChanged: (s) => setState(() => _filter = s.first),
              showSelectedIcon: false,
            ),
          ),
          Expanded(
            child: goals.isEmpty
                ? _EmptyState(filter: _filter)
                : _GoalList(goals: goals),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final _GoalFilter filter;

  const _EmptyState({required this.filter});

  @override
  Widget build(BuildContext context) {
    final isCompleted = filter == _GoalFilter.completed;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isCompleted ? Icons.check_circle_outline : Icons.flag_outlined,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(isCompleted ? 'No completed goals yet' : 'No goals yet'),
          const SizedBox(height: 4),
          Text(
            isCompleted
                ? 'Complete all subtasks on a goal to see it here'
                : 'Tap + to add your first goal',
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
    final isDecomposing =
        context.watch<DecompositionState>().isDecomposing(goal.goalId);

    return Slidable(
      key: ValueKey(goal.goalId),
      endActionPane: ActionPane(
        motion: const BehindMotion(),
        extentRatio: 0.28,
        children: [
          SlidableAction(
            onPressed: (_) => service.archiveGoal(goal.goalId),
            backgroundColor: AppColors.muted,
            foregroundColor: Colors.white,
            icon: Icons.archive_outlined,
            label: 'Archive',
          ),
        ],
      ),
      child: ListTile(
        title: Text(goal.title),
        subtitle: Text(
          isDecomposing ? 'Generating subtasks…' : _subtitleFor(goal),
        ),
        leading: isDecomposing
            ? const _SpinnerLeading()
            : _StatusBadge(status: goal.status),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (goal.status == GoalStatus.active)
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

class _SpinnerLeading extends StatelessWidget {
  const _SpinnerLeading();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 24,
      height: 24,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
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
    GoalStatus.archived => Icons.archive_outlined,
  };

  Color _colorFor(GoalStatus status) => switch (status) {
    GoalStatus.inbox => AppColors.muted,
    GoalStatus.active => AppColors.accent,
    GoalStatus.completed => AppColors.success,
    GoalStatus.archived => AppColors.muted,
  };
}
