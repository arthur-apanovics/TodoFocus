import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/enums.dart';
import '../models/goal.dart';
import '../models/sub_task.dart';
import '../services/goal_decomposition_service.dart';
import '../services/goal_repository.dart';
import '../services/goal_service.dart';
import '../theme/app_colors.dart';
import 'goal_planning_screen.dart' show SubTaskTile;
import 'widgets/goal_symbol.dart';

// Execution-focused view for an active goal. The planning screen is for
// shaping subtasks; this screen is for completing them. Tapping "Edit" in
// the AppBar opens the planning screen in `isEditingActive` mode.
class GoalActiveScreen extends StatefulWidget {
  final String goalId;
  // Set when arriving from the "Break it down" notification action — fires
  // an LLM breakdown of the current subtask once the screen mounts.
  final bool triggerBreakdown;

  const GoalActiveScreen({
    super.key,
    required this.goalId,
    this.triggerBreakdown = false,
  });

  @override
  State<GoalActiveScreen> createState() => _GoalActiveScreenState();
}

class _GoalActiveScreenState extends State<GoalActiveScreen> {
  bool _completionAnnounced = false;

  @override
  void initState() {
    super.initState();
    if (widget.triggerBreakdown) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _autoBreakdown();
      });
    }
  }

  // Called once on arrival when the user tapped "Break it down" on a
  // notification. Best-effort: silently no-ops if the current subtask is
  // gone or no LLM client is configured (the user can tap split manually).
  Future<void> _autoBreakdown() async {
    final repo = context.read<GoalRepository>();
    final goal = repo.findById(widget.goalId);
    if (goal == null) return;
    final subtask = goal.currentSubTask;
    if (subtask == null) return;

    final decomp = context.read<GoalDecompositionService>();
    final service = context.read<GoalService>();
    if (!decomp.canAutoBreakdown) return;

    final descriptions = await decomp.breakdownSubtask(subtask.description);
    if (!mounted || descriptions == null) return;
    service.splitSubTask(widget.goalId, subtask.subtaskId, descriptions);
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<GoalRepository>();
    final goal = repository.findById(widget.goalId);

    if (goal == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.pop(context);
      });
      return const SizedBox.shrink();
    }

    // Goal just transitioned to completed (last subtask checked off on
    // this screen) — announce + pop back to the Goals tab once. The flag
    // prevents repeat triggers if the user re-enters the completed goal.
    if (goal.status == GoalStatus.completed && !_completionAnnounced) {
      _completionAnnounced = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Goal complete!')),
        );
        Navigator.pop(context);
      });
    }

    final isCompleted = goal.status == GoalStatus.completed;

    return Scaffold(
      appBar: AppBar(
        title: goal.emoji != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GoalSymbol(name: goal.emoji, size: 22),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(goal.title, overflow: TextOverflow.ellipsis),
                  ),
                ],
              )
            : Text(goal.title, overflow: TextOverflow.ellipsis),
        actions: [
          // Completed goals are locked from editing — keeps the user from
          // accidentally re-opening planning on a finished goal.
          if (!isCompleted)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit goal',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GoalPlanningScreen(
                    goalId: goal.goalId,
                    isEditingActive: true,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProgressHeader(goal: goal),
          Expanded(child: _SubtaskList(goal: goal)),
        ],
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  final Goal goal;

  const _ProgressHeader({required this.goal});

  @override
  Widget build(BuildContext context) {
    final total = goal.subtasks.length;
    final done = goal.completedSubtaskCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: goal.progressPercent,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$done/$total',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            total == 0
                ? 'No subtasks yet'
                : '$done of $total complete',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.muted,
                ),
          ),
        ],
      ),
    );
  }
}

class _SubtaskList extends StatelessWidget {
  final Goal goal;

  const _SubtaskList({required this.goal});

  @override
  Widget build(BuildContext context) {
    if (goal.subtasks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No subtasks. Tap edit to plan this goal.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted),
          ),
        ),
      );
    }
    return CustomScrollView(
      slivers: [
        SliverReorderableList(
          itemCount: goal.subtasks.length,
          onReorder: (oldIndex, newIndex) {
            context
                .read<GoalService>()
                .reorderSubTask(goal.goalId, oldIndex, newIndex);
          },
          itemBuilder: (context, index) {
            final subtask = goal.subtasks[index];
            return ReorderableDelayedDragStartListener(
              key: ValueKey(subtask.subtaskId),
              index: index,
              enabled: subtask.state == SubTaskState.pending,
              child: SubTaskTile(
                subtask: subtask,
                goal: goal,
                showCompletion: true,
              ),
            );
          },
        ),
      ],
    );
  }
}
