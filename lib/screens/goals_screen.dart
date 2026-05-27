import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/enums.dart';
import '../models/goal.dart';
import '../models/sub_task.dart';
import '../services/daily_reset_service.dart';
import '../services/decomposition_state.dart';
import '../services/display_preferences.dart';
import '../services/draft_service.dart';
import '../services/focus_list_service.dart';
import '../services/goal_decomposition_service.dart';
import '../services/goal_queries.dart';
import '../services/goal_repository.dart';
import '../services/goal_service.dart';
import '../services/settings/llm_settings_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_palette.dart';
import 'goal_planning_screen.dart';
import 'widgets/estimate_picker_sheet.dart';
import 'widgets/goal_symbol.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  bool _selectMode = false;
  final Set<String> _selectedIds = {};
  bool _showCompleted = false;

  void _enterSelectMode(String goalId) {
    setState(() {
      _selectMode = true;
      _selectedIds.add(goalId);
    });
  }

  void _toggleSelection(String goalId) {
    setState(() {
      if (_selectedIds.contains(goalId)) {
        _selectedIds.remove(goalId);
        if (_selectedIds.isEmpty) _selectMode = false;
      } else {
        _selectedIds.add(goalId);
      }
    });
  }

  void _exitSelectMode() {
    setState(() {
      _selectMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _archiveSelected() async {
    final service = context.read<GoalService>();
    final ids = Set<String>.from(_selectedIds);
    _exitSelectMode();
    for (final id in ids) {
      service.archiveGoal(id);
    }
  }

  Future<void> _redecomposeSelected(List<Goal> visibleGoals) async {
    if (context.read<LlmSettingsService>().buildClient() == null) return;
    final activeGoals = visibleGoals
        .where(
          (g) =>
              _selectedIds.contains(g.goalId) && g.status == GoalStatus.active,
        )
        .toList();
    if (activeGoals.isEmpty) return;

    final draft = context.read<DraftService>();
    final instructions = await showDialog<String>(
      context: context,
      builder: (_) => _RedecomposeDialog(
        count: activeGoals.length,
        draftService: draft,
      ),
    );
    if (instructions == null || !mounted) return;
    draft.clearBulkRedecomposeInstructions();

    final decompositionService = context.read<GoalDecompositionService>();
    final decompositionState = context.read<DecompositionState>();
    final goalService = context.read<GoalService>();
    final messenger = ScaffoldMessenger.of(context);
    final debugMode = context.read<LlmSettingsService>().debugMode;
    final trimmed = instructions.trim().isEmpty ? null : instructions.trim();
    _exitSelectMode();

    for (final goal in activeGoals) {
      _redecomposeInBackground(
        goal: goal,
        instructions: trimmed,
        decompositionService: decompositionService,
        decompositionState: decompositionState,
        goalService: goalService,
        messenger: messenger,
        debugMode: debugMode,
      );
    }
  }

  // Fire-and-forget: marks the goal as decomposing, fetches new subtasks, then
  // writes them back. Intentionally not awaited at the call site.
  // [messenger] and [debugMode] are captured by the caller before the loop so
  // they remain valid even if this widget rebuilds or is disposed mid-flight.
  Future<void> _redecomposeInBackground({
    required Goal goal,
    required String? instructions,
    required GoalDecompositionService decompositionService,
    required DecompositionState decompositionState,
    required GoalService goalService,
    required ScaffoldMessengerState messenger,
    required bool debugMode,
  }) async {
    Object? llmError;
    decompositionState.begin(goal.goalId);
    try {
      final descriptions = await decompositionService.redecomposeSubtasks(
        goal.title,
        description: goal.notes.isEmpty ? null : goal.notes,
        additionalInstructions: instructions,
        difficulty: goal.difficulty,
        onError: (e) => llmError = e,
      );
      if (descriptions != null) {
        goalService.replaceAllSubTasks(goal.goalId, descriptions);
      } else if (debugMode && llmError != null) {
        messenger.showSnackBar(SnackBar(
          content: Text('"${goal.title}": ${llmError.toString()}'),
        ));
      }
    } finally {
      decompositionState.end(goal.goalId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final queries = context.watch<GoalQueries>();
    final resetService = context.watch<DailyResetService>();
    final displayPrefs = context.watch<DisplayPreferences>();

    final showCompleted = _showCompleted;
    final sortOrder = displayPrefs.sortOrder;
    final goals = showCompleted
        ? queries.completedGoals
        : resetService.sortGoals(queries.goals, sortOrder);

    // For Smart sort, the categorized view is built from the same goal set
    // but split into labelled buckets.
    final useSmart = !showCompleted && sortOrder == GoalSortOrder.smart;
    final smartCategories = useSmart
        ? resetService.categorizeForSmart(queries.goals)
        : null;

    final activeSelectedCount = goals
        .where(
          (g) =>
              _selectedIds.contains(g.goalId) && g.status == GoalStatus.active,
        )
        .length;
    // Watch LlmSettingsService directly — it's a ChangeNotifier, so watch()
    // is guaranteed to rebuild this widget when the toggle or profile changes.
    final llmEnabled = context.watch<LlmSettingsService>().buildClient() != null;

    // Daily task list — only visible on the active-goals view and when enabled.
    final dailyTaskGoal = (!showCompleted && displayPrefs.dailyTaskListEnabled)
        ? queries.dailyTaskGoal
        : null;
    final completedDailyTasks = dailyTaskGoal?.subtasks
            .where((t) => t.state == SubTaskState.completed)
            .toList() ??
        const <SubTask>[];
    final doneTodaySection = completedDailyTasks.isNotEmpty
        ? _DoneTodaySection(
            goal: dailyTaskGoal!,
            tasks: completedDailyTasks,
          )
        : null;

    // Show the empty state only when there are no regular goals AND no daily
    // task card to fill the space.
    final showEmptyState = goals.isEmpty && dailyTaskGoal == null;

    return Scaffold(
      body: Column(
        children: [
          if (_selectMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: _SelectionBar(
                selectedCount: _selectedIds.length,
                activeSelectedCount: activeSelectedCount,
                llmEnabled: llmEnabled,
                onArchive: _selectedIds.isEmpty ? null : _archiveSelected,
                onRedecompose: activeSelectedCount == 0
                    ? null
                    : () => _redecomposeSelected(goals),
                onCancel: _exitSelectMode,
              ),
            ),
          if (!_selectMode)
            _GoalsControlBar(
              showCompleted: _showCompleted,
              onFilterChanged: (v) => setState(() => _showCompleted = v),
            ),
          if (dailyTaskGoal != null)
            _DailyTaskPinnedCard(goal: dailyTaskGoal),
          Expanded(
            child: showEmptyState
                ? _EmptyState(showCompleted: showCompleted)
                : goals.isEmpty
                    // Daily task card is present but no regular goals: show
                    // only the footer (done section) or a slim empty widget.
                    ? (doneTodaySection != null
                        ? ListView(
                            padding: const EdgeInsets.only(
                                bottom: kFabSafeBottomPadding),
                            children: [doneTodaySection],
                          )
                        : const SizedBox.shrink())
                    : smartCategories != null
                        ? _CategorizedGoalList(
                            categories: smartCategories,
                            selectMode: _selectMode,
                            selectedIds: _selectedIds,
                            onLongPress: _enterSelectMode,
                            onToggleSelect: _toggleSelection,
                            footer: doneTodaySection,
                          )
                        : _GoalList(
                            goals: goals,
                            selectMode: _selectMode,
                            selectedIds: _selectedIds,
                            onLongPress: _enterSelectMode,
                            onToggleSelect: _toggleSelection,
                            footer: doneTodaySection,
                          ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Selection action bar
// ---------------------------------------------------------------------------

class _SelectionBar extends StatelessWidget {
  final int selectedCount;
  final int activeSelectedCount;
  final bool llmEnabled;
  final VoidCallback? onArchive;
  final VoidCallback? onRedecompose;
  final VoidCallback onCancel;

  const _SelectionBar({
    required this.selectedCount,
    required this.activeSelectedCount,
    required this.llmEnabled,
    required this.onArchive,
    required this.onRedecompose,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cancel selection',
            onPressed: onCancel,
          ),
          Expanded(
            child: Text(
              selectedCount == 0 ? 'Select goals' : '$selectedCount selected',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          if (llmEnabled && activeSelectedCount > 0)
            IconButton(
              icon: const Icon(Icons.auto_awesome_outlined),
              tooltip: 'Regenerate',
              onPressed: onRedecompose,
            ),
          if (onArchive != null)
            IconButton(
              icon: Icon(Icons.archive_outlined),
              tooltip: 'Archive selected',
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Archive goals'),
                    content: Text(
                      'Archive $selectedCount ${selectedCount == 1 ? 'goal' : 'goals'}?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Archive'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) onArchive!();
              },
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Re-decompose instructions dialog
// ---------------------------------------------------------------------------

class _RedecomposeDialog extends StatefulWidget {
  final int count;
  final DraftService draftService;

  const _RedecomposeDialog({required this.count, required this.draftService});

  @override
  State<_RedecomposeDialog> createState() => _RedecomposeDialogState();
}

class _RedecomposeDialogState extends State<_RedecomposeDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.draftService.bulkRedecomposeInstructions,
    );
  }

  @override
  void dispose() {
    // Always persist what the user typed — caller clears after confirmed.
    widget.draftService.saveBulkRedecomposeInstructions(_controller.text);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.count == 1 ? '1 goal' : '${widget.count} goals';
    return AlertDialog(
      title: Text('Regenerate $label'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: 'Additional instructions (optional)',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => Navigator.pop(context, _controller.text),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Regenerate'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// List + tile
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  final bool showCompleted;

  const _EmptyState({required this.showCompleted});

  @override
  Widget build(BuildContext context) {
    final isCompleted = showCompleted;
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
            style: TextStyle(color: context.palette.muted),
          ),
        ],
      ),
    );
  }
}

/// Renders goals grouped by smart-sort category with sticky section labels.
class _CategorizedGoalList extends StatelessWidget {
  final List<({String label, List<Goal> goals})> categories;
  final bool selectMode;
  final Set<String> selectedIds;
  final void Function(String) onLongPress;
  final void Function(String) onToggleSelect;
  final Widget? footer;

  const _CategorizedGoalList({
    required this.categories,
    required this.selectMode,
    required this.selectedIds,
    required this.onLongPress,
    required this.onToggleSelect,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    // Build a flat list of items: section headers interleaved with goal tiles.
    final items = <Widget>[];
    for (final category in categories) {
      items.add(_SectionHeader(label: category.label));
      for (final goal in category.goals) {
        items.add(_GoalTile(
          goal: goal,
          selectMode: selectMode,
          isSelected: selectedIds.contains(goal.goalId),
          onLongPress: () => onLongPress(goal.goalId),
          onToggleSelect: () => onToggleSelect(goal.goalId),
        ));
      }
    }
    if (footer != null) items.add(footer!);
    return ListView(
      // Bottom inset lets the last goal scroll above the FAB.
      padding: const EdgeInsets.only(bottom: kFabSafeBottomPadding),
      children: items,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: context.palette.muted,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _GoalList extends StatelessWidget {
  final List<Goal> goals;
  final bool selectMode;
  final Set<String> selectedIds;
  final void Function(String) onLongPress;
  final void Function(String) onToggleSelect;
  final Widget? footer;

  const _GoalList({
    required this.goals,
    required this.selectMode,
    required this.selectedIds,
    required this.onLongPress,
    required this.onToggleSelect,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    if (footer == null) {
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: kFabSafeBottomPadding),
        itemCount: goals.length,
        itemBuilder: (context, index) {
          final goal = goals[index];
          return _GoalTile(
            goal: goal,
            selectMode: selectMode,
            isSelected: selectedIds.contains(goal.goalId),
            onLongPress: () => onLongPress(goal.goalId),
            onToggleSelect: () => onToggleSelect(goal.goalId),
          );
        },
      );
    }
    // footer present — build as a plain list so we can append it.
    return ListView(
      padding: const EdgeInsets.only(bottom: kFabSafeBottomPadding),
      children: [
        for (final goal in goals)
          _GoalTile(
            goal: goal,
            selectMode: selectMode,
            isSelected: selectedIds.contains(goal.goalId),
            onLongPress: () => onLongPress(goal.goalId),
            onToggleSelect: () => onToggleSelect(goal.goalId),
          ),
        footer!,
      ],
    );
  }
}

class _GoalTile extends StatelessWidget {
  final Goal goal;
  final bool selectMode;
  final bool isSelected;
  final VoidCallback onLongPress;
  final VoidCallback onToggleSelect;

  const _GoalTile({
    required this.goal,
    required this.selectMode,
    required this.isSelected,
    required this.onLongPress,
    required this.onToggleSelect,
  });

  @override
  Widget build(BuildContext context) {
    final isDecomposing = context.watch<DecompositionState>().isDecomposing(
      goal.goalId,
    );
    final layout = context.watch<DisplayPreferences>().layout;

    final tile = ListTile(
      onTap: selectMode
          ? onToggleSelect
          : () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GoalPlanningScreen(goalId: goal.goalId),
              ),
            ),
      onLongPress: selectMode ? null : onLongPress,
      leading: selectMode
          ? Checkbox(value: isSelected, onChanged: (_) => onToggleSelect())
          : isDecomposing
          ? const _SpinnerLeading()
          : _StatusBadge(status: goal.status, emoji: goal.emoji),
      title: Text(goal.title),
      subtitle: isDecomposing
          ? const Text('Generating subtasks…')
          : _buildSubtitle(context),
      trailing: selectMode
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (goal.status == GoalStatus.active)
                  _GoalFocusToggle(goal: goal),
                const Icon(Icons.chevron_right),
              ],
            ),
    );

    // In non-compact layouts, append an inline strip of upcoming subtasks.
    final subtasks = !isDecomposing && layout != GoalListLayout.compact
        ? _visibleSubtasks(goal, layout)
        : const <SubTask>[];

    if (subtasks.isEmpty) {
      return KeyedSubtree(key: ValueKey(goal.goalId), child: tile);
    }

    return Column(
      key: ValueKey(goal.goalId),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tile,
        _SubtaskStrip(
          subtasks: subtasks,
          currentSubtaskId: goal.currentSubTask?.subtaskId,
        ),
      ],
    );
  }

  String _formatDueDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    final diff = d.difference(today).inDays;
    if (diff == 0) return 'due today';
    if (diff == 1) return 'due tomorrow';
    if (diff == -1) return 'due yesterday';
    if (diff < 0) return '${diff.abs()}d overdue';
    if (diff <= 7) return 'due in ${diff}d';
    // Same year — show "Jan 12", different year — show "Jan 12 2026"
    final months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    final label = '${months[date.month - 1]} ${date.day}';
    return date.year == now.year ? label : '$label ${date.year}';
  }

  /// Returns the subtasks that should be shown inline for the given [layout].
  /// Always starts with the current (first pending) subtask, then adds up to N
  /// further pending subtasks in order. Returns empty if no current subtask.
  List<SubTask> _visibleSubtasks(Goal goal, GoalListLayout layout) {
    final current = goal.currentSubTask;
    if (current == null) return const [];

    final extra = switch (layout) {
      GoalListLayout.compact      => 0,
      GoalListLayout.current      => 0,
      GoalListLayout.currentPlus2 => 2,
      GoalListLayout.currentPlus4 => 4,
    };

    final result = <SubTask>[current];
    final currentIdx = goal.subtasks.indexOf(current);
    var added = 0;
    for (var i = currentIdx + 1; i < goal.subtasks.length && added < extra; i++) {
      if (goal.subtasks[i].state == SubTaskState.pending) {
        result.add(goal.subtasks[i]);
        added++;
      }
    }
    return result;
  }

  Widget _buildSubtitle(BuildContext context) {
    final hasTasks = goal.subtasks.isNotEmpty;
    final dueDate = goal.dueDate;

    // No tasks and no due date — plain label, no Row needed.
    if (!hasTasks && dueDate == null) {
      return const Text('No subtasks yet');
    }

    final prefs = context.watch<DisplayPreferences>();
    final showEstimate =
        showEstimatesForGoal(goal, prefs) && goal.hasAnyEstimate;
    final remaining = goal.remainingEstimatedMinutes;

    return Row(
      children: [
        if (hasTasks)
          SizedBox(
            width: 80,
            child: LinearProgressIndicator(
              value: goal.progressPercent,
              borderRadius: BorderRadius.circular(4),
            ),
          )
        else
          const Text('No subtasks yet'),
        // Time-left chip — only when estimates are visible AND any subtask
        // has an estimate. Prefers "left" (most actionable info while work
        // remains), falling back to "total" once everything is complete so
        // the goal still shows a meaningful number.
        if (showEstimate) ...[
          const SizedBox(width: 8),
          Icon(Icons.schedule, size: 12, color: context.palette.muted),
          const SizedBox(width: 3),
          Text(
            remaining > 0
                ? '${formatEstimate(remaining)} left'
                : '${formatEstimate(goal.totalEstimatedMinutes)} total',
            style: TextStyle(fontSize: 12, color: context.palette.muted),
          ),
        ],
        const Spacer(),
        // State indicators: recurrence ↻, snooze 💤. These sit before the
        // due date so the eye reads "what kind of goal" before "when".
        if (goal.isRecurring)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Icon(Icons.repeat, size: 12, color: context.palette.accent),
          ),
        if (goal.isOnHold)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Icon(Icons.bedtime_outlined,
                size: 12, color: context.palette.muted),
          ),
        if (dueDate != null)
          Text(
            _formatDueDate(dueDate),
            style: TextStyle(fontSize: 12, color: context.palette.muted),
          ),
      ],
    );
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
  final String? emoji;

  const _StatusBadge({required this.status, this.emoji});

  @override
  Widget build(BuildContext context) {
    if (emoji != null) return GoalSymbol(name: emoji);
    return Icon(_iconFor(status), color: _colorFor(context, status));
  }

  IconData _iconFor(GoalStatus status) => switch (status) {
    GoalStatus.inbox => Icons.inbox_outlined,
    GoalStatus.active => Icons.flag_outlined,
    GoalStatus.completed => Icons.check_circle_outline,
    GoalStatus.archived => Icons.archive_outlined,
  };

  Color _colorFor(BuildContext context, GoalStatus status) => switch (status) {
    GoalStatus.inbox => context.palette.muted,
    GoalStatus.active => context.palette.accent,
    GoalStatus.completed => context.palette.success,
    GoalStatus.archived => context.palette.muted,
  };
}

// Compact inline list of pending subtasks rendered beneath a goal tile.
// The current step uses a hollow-circle icon (mirrors the execution screen);
// subsequent queued steps use the nextInQueue arrow to signal ordering.
class _SubtaskStrip extends StatelessWidget {
  final List<SubTask> subtasks;
  final String? currentSubtaskId;

  const _SubtaskStrip({
    required this.subtasks,
    required this.currentSubtaskId,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Align with ListTile content
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: subtasks.map((subtask) {
          final isCurrent = subtask.subtaskId == currentSubtaskId;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(
                  isCurrent ? AppIcons.currentSubtask : AppIcons.nextInQueue,
                  size: 14,
                  color: isCurrent ? cs.onSurface : context.palette.muted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    subtask.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isCurrent ? cs.onSurface : context.palette.muted,
                          fontWeight: isCurrent
                              ? FontWeight.w500
                              : FontWeight.normal,
                        ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// Inline trailing toggle on each goal row. Tapping flips the whole goal's
// "fully focused" intent — adds every pending subtask to the focus list, and
// marks future additions to auto-join. Star is filled when ANY subtask of
// this goal is in the list (signals "this goal is on today's plate"), even
// if the user only manually focused a subset.
class _GoalFocusToggle extends StatelessWidget {
  final Goal goal;

  const _GoalFocusToggle({required this.goal});

  @override
  Widget build(BuildContext context) {
    final focus = context.watch<FocusListService>();
    final fullyFocused = focus.isGoalFullyFocused(goal.goalId);
    final hasAny = focus.hasFocus(goal.goalId);
    return IconButton(
      icon: Icon(
        hasAny ? Icons.star : Icons.star_border,
        color: hasAny ? context.palette.accent : context.palette.muted,
      ),
      tooltip:
          fullyFocused ? 'Remove from Today' : 'Add all pending to Today',
      onPressed: () {
        final f = context.read<FocusListService>();
        if (fullyFocused) {
          f.unfocusGoalFully(goal.goalId);
        } else {
          f.focusGoalFully(goal.goalId, context.read<GoalRepository>());
        }
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Daily task list — pinned card and done-today section
// ---------------------------------------------------------------------------

class _DailyTaskPinnedCard extends StatelessWidget {
  final Goal goal;

  const _DailyTaskPinnedCard({required this.goal});

  @override
  Widget build(BuildContext context) {
    final pendingTasks =
        goal.subtasks.where((t) => t.state == SubTaskState.pending).toList();
    final hasTasks = goal.subtasks.isNotEmpty;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GoalPlanningScreen(goalId: goal.goalId),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  goal.emoji != null
                      ? GoalSymbol(name: goal.emoji)
                      : Icon(Icons.checklist_outlined,
                          size: 20, color: context.palette.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      goal.title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  _GoalFocusToggle(goal: goal),
                  const Icon(Icons.chevron_right),
                ],
              ),
              if (hasTasks) ...[
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: goal.progressPercent,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 4),
                Text(
                  pendingTasks.isEmpty
                      ? 'All done for today!'
                      : pendingTasks.first.description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.palette.muted,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Tap to add today\'s tasks',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.palette.muted,
                        ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DoneTodaySection extends StatefulWidget {
  final Goal goal;
  final List<SubTask> tasks;

  const _DoneTodaySection({required this.goal, required this.tasks});

  @override
  State<_DoneTodaySection> createState() => _DoneTodaySectionState();
}

class _DoneTodaySectionState extends State<_DoneTodaySection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final count = widget.tasks.length;

    return ColoredBox(
      color: cs.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 16, color: context.palette.success),
                  const SizedBox(width: 8),
                  Text(
                    'Done today ($count)',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: context.palette.muted,
                        ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: context.palette.muted,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            for (final task in widget.tasks)
              Padding(
                padding: const EdgeInsets.fromLTRB(40, 0, 16, 6),
                child: Text(
                  task.description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.palette.muted,
                        decoration: TextDecoration.lineThrough,
                      ),
                ),
              ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Goals tab control bar — filter, sort, layout (moved from AppShell)
// ---------------------------------------------------------------------------

class _GoalsControlBar extends StatelessWidget {
  final bool showCompleted;
  final ValueChanged<bool> onFilterChanged;

  const _GoalsControlBar({
    required this.showCompleted,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    final displayPrefs = context.watch<DisplayPreferences>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
      child: Row(
        children: [
          SegmentedButton<bool>(
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              textStyle: Theme.of(context).textTheme.labelSmall,
            ),
            segments: const [
              ButtonSegment(value: false, label: Text('Active')),
              ButtonSegment(value: true, label: Text('Done')),
            ],
            selected: {showCompleted},
            onSelectionChanged: (s) => onFilterChanged(s.first),
            showSelectedIcon: false,
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort goals',
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (_) => _SortSheet(
                current: displayPrefs.sortOrder,
                onSelected: context.read<DisplayPreferences>().setSortOrder,
              ),
            ),
          ),
          PopupMenuButton<GoalListLayout>(
            icon: const Icon(Icons.view_agenda_outlined),
            tooltip: 'List layout',
            onSelected: context.read<DisplayPreferences>().setLayout,
            itemBuilder: (_) => GoalListLayout.values
                .map(
                  (v) => PopupMenuItem(
                    value: v,
                    child: ListTile(
                      title: Text(v.displayName),
                      trailing: displayPrefs.layout == v
                          ? const Icon(Icons.check, size: 18)
                          : null,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      minLeadingWidth: 24,
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _SortSheet extends StatelessWidget {
  final GoalSortOrder current;
  final void Function(GoalSortOrder) onSelected;

  const _SortSheet({required this.current, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              'Sort goals',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          _SortTile(
            label: 'Date added',
            subtitle: 'Oldest first',
            icon: Icons.calendar_today_outlined,
            selected: current == GoalSortOrder.dateAdded,
            onTap: () { onSelected(GoalSortOrder.dateAdded); Navigator.pop(context); },
          ),
          _SortTile(
            label: 'Urgency',
            subtitle: 'Near deadlines → previously assigned → rest',
            icon: Icons.priority_high,
            selected: current == GoalSortOrder.urgency,
            onTap: () { onSelected(GoalSortOrder.urgency); Navigator.pop(context); },
          ),
          _SortTile(
            label: 'Smart',
            subtitle: 'Same as urgency — recommended default',
            icon: Icons.auto_awesome_outlined,
            selected: current == GoalSortOrder.smart,
            onTap: () { onSelected(GoalSortOrder.smart); Navigator.pop(context); },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _SortTile extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SortTile({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon,
          color: selected ? Theme.of(context).colorScheme.primary : null),
      title: Text(label,
          style: selected
              ? TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                )
              : null),
      subtitle: Text(subtitle),
      trailing: selected ? const Icon(Icons.check) : null,
      onTap: onTap,
    );
  }
}
