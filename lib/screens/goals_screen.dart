import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/goal.dart';
import '../models/enums.dart';
import '../services/daily_reset_service.dart';
import '../services/decomposition_state.dart';
import '../services/draft_service.dart';
import '../services/goal_decomposition_service.dart';
import '../services/goal_queries.dart';
import '../services/goal_service.dart';
import '../services/settings/llm_settings_service.dart';
import '../theme/app_colors.dart';
import 'goal_active_screen.dart';
import 'widgets/goal_symbol.dart';

class GoalsScreen extends StatefulWidget {
  final ValueNotifier<bool> showCompletedNotifier;

  const GoalsScreen({super.key, required this.showCompletedNotifier});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  bool _selectMode = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    widget.showCompletedNotifier.addListener(_onFilterChanged);
  }

  void _onFilterChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.showCompletedNotifier.removeListener(_onFilterChanged);
    super.dispose();
  }

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
    final trimmed = instructions.trim().isEmpty ? null : instructions.trim();
    _exitSelectMode();

    for (final goal in activeGoals) {
      _redecomposeInBackground(
        goal: goal,
        instructions: trimmed,
        decompositionService: decompositionService,
        decompositionState: decompositionState,
        goalService: goalService,
      );
    }
  }

  // Fire-and-forget: marks the goal as decomposing, fetches new subtasks, then
  // writes them back. Intentionally not awaited at the call site.
  Future<void> _redecomposeInBackground({
    required Goal goal,
    required String? instructions,
    required GoalDecompositionService decompositionService,
    required DecompositionState decompositionState,
    required GoalService goalService,
  }) async {
    decompositionState.begin(goal.goalId);
    try {
      final descriptions = await decompositionService.redecomposeSubtasks(
        goal.title,
        description: goal.notes.isEmpty ? null : goal.notes,
        additionalInstructions: instructions,
        difficulty: goal.difficulty,
      );
      if (descriptions != null) {
        goalService.replaceAllSubTasks(goal.goalId, descriptions);
      }
    } finally {
      decompositionState.end(goal.goalId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final queries = context.watch<GoalQueries>();
    final resetService = context.watch<DailyResetService>();

    final showCompleted = widget.showCompletedNotifier.value;
    final goals = showCompleted
        ? queries.completedGoals
        : resetService.sortGoals(queries.goals, resetService.sortOrder);

    final activeSelectedCount = goals
        .where(
          (g) =>
              _selectedIds.contains(g.goalId) && g.status == GoalStatus.active,
        )
        .length;
    // Watch LlmSettingsService directly — it's a ChangeNotifier, so watch()
    // is guaranteed to rebuild this widget when the toggle or profile changes.
    final llmEnabled = context.watch<LlmSettingsService>().buildClient() != null;

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
          Expanded(
            child: goals.isEmpty
                ? _EmptyState(showCompleted: showCompleted)
                : _GoalList(
                    goals: goals,
                    selectMode: _selectMode,
                    selectedIds: _selectedIds,
                    onLongPress: _enterSelectMode,
                    onToggleSelect: _toggleSelection,
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
            style: TextStyle(color: AppColors.muted),
          ),
        ],
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

  const _GoalList({
    required this.goals,
    required this.selectMode,
    required this.selectedIds,
    required this.onLongPress,
    required this.onToggleSelect,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
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
    final service = context.read<GoalService>();
    final isDecomposing = context.watch<DecompositionState>().isDecomposing(
      goal.goalId,
    );

    return ListTile(
      key: ValueKey(goal.goalId),
      onTap: selectMode
          ? onToggleSelect
          : () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GoalActiveScreen(goalId: goal.goalId),
              ),
            ),
      onLongPress: selectMode ? null : onLongPress,
      leading: selectMode
          ? Checkbox(value: isSelected, onChanged: (_) => onToggleSelect())
          : isDecomposing
          ? const _SpinnerLeading()
          : _StatusBadge(status: goal.status, emoji: goal.emoji),
      title: goal.dueDate != null
          ? Row(
              children: [
                Expanded(child: Text(goal.title)),
                const SizedBox(width: 8),
                Text(
                  _formatDueDate(goal.dueDate!),
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            )
          : Text(goal.title),
      subtitle: Text(
        isDecomposing ? 'Generating subtasks…' : _subtitleFor(goal),
      ),
      trailing: selectMode
          ? null
          : Row(
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

  String _subtitleFor(Goal goal) {
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
  final String? emoji;

  const _StatusBadge({required this.status, this.emoji});

  @override
  Widget build(BuildContext context) {
    if (emoji != null) return GoalSymbol(name: emoji);
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
