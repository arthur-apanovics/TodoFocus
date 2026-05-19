import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/enums.dart';
import '../models/goal.dart';
import '../services/focus_list_service.dart';
import '../services/goal_decomposition_service.dart';
import '../services/goal_repository.dart';
import '../services/goal_service.dart';
import '../theme/app_colors.dart';
import 'goal_planning_screen.dart' show GoalPlanningScreen, SubTaskTile;
import 'widgets/goal_symbol.dart';

enum _GoalAction { plan, archive, sendToPlanning }

// Execution-focused view for an active or completed goal. The planning screen
// is for shaping subtasks; this screen is for completing them. The three-dot
// menu opens the planning screen ("Plan"), archives, or sends back to planning.
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
  // True when the goal was active at the moment this screen was pushed.
  // Used to distinguish "just finished" (pop + celebrate) from "navigated
  // to an already-completed goal" (render read-only view, no pop).
  bool _wasActive = false;

  @override
  void initState() {
    super.initState();
    _wasActive =
        context.read<GoalRepository>().findById(widget.goalId)?.status ==
            GoalStatus.active;
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

    final completedSteps = goal.subtasks
        .where((s) => s.isCompleted)
        .map((s) => s.description)
        .toList();
    final otherPendingSteps = goal.subtasks
        .where((s) => !s.isCompleted && s.subtaskId != subtask.subtaskId)
        .map((s) => s.description)
        .toList();

    final descriptions = await decomp.breakdownSubtask(
      subtask.description,
      goalTitle: goal.title,
      goalDescription: goal.notes.isNotEmpty ? goal.notes : null,
      difficulty: goal.difficulty,
      completedSteps: completedSteps.isNotEmpty ? completedSteps : null,
      otherPendingSteps:
          otherPendingSteps.isNotEmpty ? otherPendingSteps : null,
    );
    if (!mounted || descriptions == null) return;
    service.splitSubTask(widget.goalId, subtask.subtaskId, descriptions);
  }

  void _handleAction(BuildContext context, Goal goal, _GoalAction action) {
    final service = context.read<GoalService>();
    switch (action) {
      case _GoalAction.plan:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GoalPlanningScreen(
              goalId: goal.goalId,
              isEditingActive: true,
            ),
          ),
        );
      case _GoalAction.archive:
        service.archiveGoal(goal.goalId);
        Navigator.pop(context);
      case _GoalAction.sendToPlanning:
        service.sendToPlanning(goal.goalId);
        Navigator.pop(context);
    }
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

    final isCompleted = goal.status == GoalStatus.completed;

    // Goal just transitioned to completed while the user was on this screen
    // (last subtask checked off here). Celebrate + pop back once.
    if (isCompleted && _wasActive && !_completionAnnounced) {
      _completionAnnounced = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Goal complete!')),
        );
        Navigator.pop(context);
      });
    }

    // Suppress rendering during the async pop frame.
    if (isCompleted && _wasActive && _completionAnnounced) {
      return const SizedBox.shrink();
    }

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
          PopupMenuButton<_GoalAction>(
            onSelected: (action) => _handleAction(context, goal, action),
            itemBuilder: (_) => [
              if (!isCompleted) ...[
                const PopupMenuItem(
                  value: _GoalAction.plan,
                  child: ListTile(
                    leading: Icon(Icons.edit_note_outlined),
                    title: Text('Plan'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: _GoalAction.archive,
                  child: ListTile(
                    leading: Icon(Icons.archive_outlined),
                    title: Text('Archive'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
              if (isCompleted)
                const PopupMenuItem(
                  value: _GoalAction.sendToPlanning,
                  child: ListTile(
                    leading: Icon(Icons.edit_note_outlined),
                    title: Text('Send to Planning'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GoalHeader(goal: goal),
          if (isCompleted)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                'Read-only — send to Planning to re-queue',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.muted,
                    ),
              ),
            ),
          Expanded(child: _SubtaskList(goal: goal, readOnly: isCompleted)),
        ],
      ),
      bottomNavigationBar: isCompleted ? null : _FocusBar(goal: goal),
    );
  }
}

class _GoalHeader extends StatelessWidget {
  final Goal goal;

  const _GoalHeader({required this.goal});

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatDueDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(d.year, d.month, d.day);
    final diff = date.difference(today).inDays;
    if (diff == 0) return 'Due today';
    if (diff == 1) return 'Due tomorrow';
    if (diff == -1) return 'Due yesterday';
    if (diff < 0) return '${diff.abs()}d overdue';
    if (diff <= 7) return 'Due in ${diff}d';
    final label = '${_months[d.month - 1]} ${d.day}';
    return 'Due ${d.year == now.year ? label : '$label ${d.year}'}';
  }

  @override
  Widget build(BuildContext context) {
    final total = goal.subtasks.length;
    final done = goal.completedSubtaskCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (goal.notes.isNotEmpty) ...[
            Text(goal.notes, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
          ],
          if (goal.dueDate != null) ...[
            Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 14,
                  color: AppColors.muted,
                ),
                const SizedBox(width: 4),
                Text(
                  _formatDueDate(goal.dueDate!),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.muted,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
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

// Sticky bottom bar that toggles the whole goal in/out of today's focus.
// When tapped to focus, every currently-pending subtask is appended to the
// focus list AND the goal is marked "fully focused" so future subtasks
// added to this goal auto-join the list too. Tapping again removes the
// goal-level intent and drops every entry belonging to this goal.
class _FocusBar extends StatelessWidget {
  final Goal goal;

  const _FocusBar({required this.goal});

  @override
  Widget build(BuildContext context) {
    final focus = context.watch<FocusListService>();
    final fullyFocused = focus.isGoalFullyFocused(goal.goalId);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: fullyFocused
            ? OutlinedButton.icon(
                icon: const Icon(Icons.star_rounded),
                label: const Text('Goal in focus — tap to remove'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () => context
                    .read<FocusListService>()
                    .unfocusGoalFully(goal.goalId),
              )
            : FilledButton.icon(
                icon: const Icon(Icons.star_outline_rounded),
                label: const Text('Add all pending to today\'s focus'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () => context
                    .read<FocusListService>()
                    .focusGoalFully(goal.goalId, context.read<GoalRepository>()),
              ),
      ),
    );
  }
}

class _SubtaskList extends StatelessWidget {
  final Goal goal;
  final bool readOnly;

  const _SubtaskList({required this.goal, this.readOnly = false});

  @override
  Widget build(BuildContext context) {
    if (goal.subtasks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No subtasks. Use the menu to plan this goal.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted),
          ),
        ),
      );
    }

    if (readOnly) {
      return ListView.builder(
        itemCount: goal.subtasks.length,
        itemBuilder: (context, index) {
          final subtask = goal.subtasks[index];
          return SubTaskTile(
            key: ValueKey(subtask.subtaskId),
            subtask: subtask,
            goal: goal,
            showCompletion: false,
          );
        },
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
