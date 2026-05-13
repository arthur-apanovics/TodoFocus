import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import '../models/enums.dart';
import '../models/goal.dart';
import '../models/sub_task.dart';
import '../services/decomposition_state.dart';
import '../services/goal_decomposition_service.dart';
import '../services/goal_repository.dart';
import '../services/goal_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import 'widgets/app_bottom_sheet.dart';

const addSubtaskIcon = Icons.playlist_add;

class GoalDetailScreen extends StatefulWidget {
  final String goalId;
  final bool triggerBreakdown;

  const GoalDetailScreen({
    super.key,
    required this.goalId,
    this.triggerBreakdown = false,
  });

  @override
  State<GoalDetailScreen> createState() => _GoalDetailScreenState();
}

class _GoalDetailScreenState extends State<GoalDetailScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.triggerBreakdown) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _autoBreakdown();
      });
    }
  }

  // Triggered by the "Break it down" notification action. Attempts LLM breakdown
  // of the current subtask immediately; falls back to the manual split sheet.
  Future<void> _autoBreakdown() async {
    final repo = context.read<GoalRepository>();
    final goal = repo.findById(widget.goalId);
    if (goal == null) return;
    final subtask = goal.currentSubTask;
    if (subtask == null) return;

    final decomp = context.read<GoalDecompositionService>();
    final service = context.read<GoalService>();

    if (!decomp.canAutoBreakdown) {
      _showManualSplit(subtask, service);
      return;
    }

    final descriptions = await decomp.breakdownSubtask(subtask.description);
    if (!mounted) return;

    if (descriptions == null) {
      _showManualSplit(subtask, service);
      return;
    }

    service.splitSubTask(widget.goalId, subtask.subtaskId, descriptions);
  }

  void _showManualSplit(SubTask subtask, GoalService service) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SubTaskSplitSheet(
        goalId: widget.goalId,
        subtask: subtask,
        goalService: service,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch the repository directly so we rebuild when any goal changes
    final repository = context.watch<GoalRepository>();
    final goal = repository.findById(widget.goalId);

    // Guard against the goal being deleted while this screen is open
    if (goal == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.pop(context);
      });
      return const SizedBox.shrink();
    }

    final isDecomposing =
        context.watch<DecompositionState>().isDecomposing(widget.goalId);

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => _showEditGoalSheet(context, goal),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(goal.title, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.edit_outlined, size: 16),
            ],
          ),
        ),
        actions: [_GoalMenuButton(goal: goal)],
      ),
      body: CustomScrollView(
        slivers: [
          // Metadata card
          SliverToBoxAdapter(child: _GoalMetadataCard(goal: goal)),
          // Section header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Subtasks',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          // Loading state while decomposition is in flight
          if (isDecomposing)
            const SliverToBoxAdapter(child: _DecomposingState())
          // Inbox item waiting for the user to decide what to do with it
          else if (goal.status == GoalStatus.inbox)
            SliverToBoxAdapter(child: _InboxReadyState(goal: goal))
          // Reorderable subtask list
          else if (goal.subtasks.isEmpty)
            const SliverToBoxAdapter(child: _EmptySubtaskState())
          else
            SliverReorderableList(
              itemCount: goal.subtasks.length,
              onReorder: (oldIndex, newIndex) {
                final service = context.read<GoalService>();
                service.reorderSubTask(widget.goalId, oldIndex, newIndex);
              },
              itemBuilder: (context, index) {
                final subtask = goal.subtasks[index];
                return SubTaskTile(
                  key: ValueKey(subtask.subtaskId),
                  subtask: subtask,
                  goal: goal,
                  index: index,
                );
              },
            ),
        ],
      ),
      floatingActionButton: isDecomposing
          ? null
          : FloatingActionButton(
              onPressed: () => _showAddSubTaskSheet(context),
              tooltip: 'Add subtask',
              child: const Icon(addSubtaskIcon),
            ),
    );
  }

  void _showEditGoalSheet(BuildContext context, Goal goal) {
    final service = context.read<GoalService>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _GoalEditSheet(goal: goal, goalService: service),
    );
  }

  void _showAddSubTaskSheet(BuildContext context) {
    final service = context.read<GoalService>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SubTaskSheet(goalId: widget.goalId, goalService: service),
    );
  }
}

// --- Metadata card ---

class _GoalMetadataCard extends StatelessWidget {
  final Goal goal;

  const _GoalMetadataCard({required this.goal});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (goal.notes.isNotEmpty) ...[
              Text(goal.notes),
              const SizedBox(height: 12),
            ],
            // Progress indicator
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
                  '${goal.completedSubtaskCount}/${goal.subtasks.length}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            if (goal.dueDate != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.calendar_today_outlined, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    'Due ${goal.dueDate!.day}/${goal.dueDate!.month}/${goal.dueDate!.year}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// --- Goal menu (delete) ---

class _GoalEditSheet extends StatefulWidget {
  final Goal goal;
  final GoalService goalService;

  const _GoalEditSheet({required this.goal, required this.goalService});

  @override
  State<_GoalEditSheet> createState() => _GoalEditSheetState();
}

class _GoalEditSheetState extends State<_GoalEditSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  final _notesFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.goal.title);
    _notesController = TextEditingController(text: widget.goal.notes);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    widget.goalService.updateGoal(
      widget.goal.goalId,
      title: title,
      notes: _notesController.text.trim(),
    );

    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AppBottomSheet(
      title: 'Edit goal',
      children: [
        TextField(
          controller: _titleController,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _notesFocus.requestFocus(),
          decoration: const InputDecoration(
            labelText: 'Title',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notesController,
          focusNode: _notesFocus,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Description',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: _submit, child: const Text('Save changes')),
      ],
    );
  }
}

class _GoalMenuButton extends StatelessWidget {
  final Goal goal;

  const _GoalMenuButton({required this.goal});

  @override
  Widget build(BuildContext context) {
    final service = context.read<GoalService>();
    final canRedecompose =
        context.read<GoalDecompositionService>().canAutoBreakdown;

    return PopupMenuButton<String>(
      onSelected: (value) {
        switch (value) {
          case 'redecompose':
            _confirmRedecompose(context, service);
          case 'delete':
            _confirmDelete(context, service);
        }
      },
      itemBuilder: (_) => [
        if (canRedecompose)
          const PopupMenuItem(
            value: 'redecompose',
            child: Text('Re-decompose subtasks'),
          ),
        PopupMenuItem(
          value: 'delete',
          child: Text(
            'Delete goal',
            style: TextStyle(color: AppColors.destructive),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmRedecompose(
    BuildContext context,
    GoalService service,
  ) async {
    final decomp = context.read<GoalDecompositionService>();

    // Returns the instructions string on confirm, null on cancel.
    // Using a StatefulWidget dialog so the TextEditingController is disposed
    // after the exit animation — not while the TextField is still in the tree.
    final instructions = await showDialog<String>(
      context: context,
      builder: (_) => const _RedecomposeDialog(),
    );

    if (instructions == null) return;
    if (!context.mounted) return;

    final decompState = context.read<DecompositionState>();
    final messenger = ScaffoldMessenger.of(context);

    decompState.begin(goal.goalId);
    try {
      final descriptions = await decomp.redecomposeSubtasks(
        goal.title,
        description: goal.notes.isEmpty ? null : goal.notes,
        additionalInstructions: instructions.isEmpty ? null : instructions,
      );
      if (descriptions == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text("Couldn't re-decompose subtasks")),
        );
        return;
      }
      service.replaceAllSubTasks(goal.goalId, descriptions);
    } finally {
      decompState.end(goal.goalId);
    }
  }

  void _confirmDelete(BuildContext context, GoalService service) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete goal?'),
        content: const Text('This will delete the goal and all its subtasks.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.destructive,
            ),
            onPressed: () {
              Navigator.pop(context); // close dialog
              service.removeGoal(goal.goalId);
              // GoalDetailScreen.build null-guard pops the detail screen
              // when it rebuilds and finds goal == null.
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// --- Subtask tile ---

class SubTaskTile extends StatefulWidget {
  final SubTask subtask;
  final Goal goal; // need the parent goal to check isCurrentSubTask
  final int index;

  const SubTaskTile({
    super.key,
    required this.subtask,
    required this.goal,
    required this.index,
  });

  @override
  State<SubTaskTile> createState() => _SubTaskTileState();
}

class _SubTaskTileState extends State<SubTaskTile> {
  // Locks editing, swiping, dragging, and the trailing action while the
  // breakdown provider is being awaited.
  bool _isBreakingDown = false;

  SubTask get subtask => widget.subtask;
  Goal get goal => widget.goal;
  int get index => widget.index;

  @override
  Widget build(BuildContext context) {
    final service = context.read<GoalService>();
    final isCurrent = goal.isCurrentSubTask(subtask);
    final isCompleted = subtask.isCompleted;
    final isPending = !isCompleted;

    // Slidable instead of Dismissible:
    //  - Doesn't try to auto-remove the row, so it never collides with the
    //    Provider rebuild that follows service.deleteSubTask().
    //  - Has narrower gesture territory than Dismissible, so the trailing
    //    IconButton's tap recogniser actually wins the gesture arena
    //    instead of being swallowed by a horizontal-pan recogniser
    //    watching the whole tile.
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Slidable(
        key: ValueKey(subtask.subtaskId),
        // Disable swipe-to-delete during breakdown — otherwise the user could
        // delete the row while the result is in flight and the response would
        // silently miss its target.
        enabled: !_isBreakingDown,
        endActionPane: ActionPane(
          motion: const BehindMotion(),
          extentRatio: 0.25,
          children: [
            SlidableAction(
              onPressed: (_) =>
                  service.deleteSubTask(goal.goalId, subtask.subtaskId),
              backgroundColor: AppColors.destructive,
              foregroundColor: AppColors.onDestructive,
              icon: AppIcons.delete,
              label: 'Delete',
            ),
          ],
        ),
        child: Opacity(
          opacity: _isBreakingDown ? 0.6 : 1.0,
          child: ListTile(
            leading: (isCompleted || _isBreakingDown)
                ? const Icon(Icons.drag_handle, color: Colors.transparent)
                : ReorderableDragStartListener(
                    index: index,
                    child: const Icon(Icons.drag_handle),
                  ),
            title: GestureDetector(
              onTap: (isPending && !_isBreakingDown)
                  ? () => _showEditSheet(context, service)
                  : null,
              child: Text(
                subtask.description,
                style: isCompleted
                    ? TextStyle(
                        decoration: TextDecoration.lineThrough,
                        color: AppColors.muted,
                      )
                    : isCurrent
                        ? TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.strong,
                          )
                        : null,
              ),
            ),
            subtitle: _isBreakingDown
                ? const Text('Breaking down…')
                : isCompleted
                    ? const Text('Completed')
                    : null,
            trailing: _buildTrailingAction(
              context,
              service,
              isCurrent,
              isCompleted,
            ),
          ),
        ),
      ),
    );
  }

  Widget? _buildTrailingAction(
    BuildContext context,
    GoalService service,
    bool isCurrent,
    bool isCompleted,
  ) {
    // While breaking down, replace the whole trailing area with a spinner so
    // nothing else can be tapped on this row.
    if (_isBreakingDown) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    // Monotone palette — three semantic shades carry the meaning.
    // See AppColors for the actual values; tweak there to experiment.
    //   faded   → completed row leading icon
    //   muted   → lock, restore  (present but secondary)
    //   strong  → primary action (the current subtask's circle)
    if (isCompleted) {
      return IconButton(
        icon: Icon(AppIcons.uncomplete, size: 20, color: AppColors.muted),
        tooltip: 'Mark incomplete',
        onPressed: () =>
            service.uncompleteSubTask(goal.goalId, subtask.subtaskId),
      );
    }

    // Split button — shown on all non-completed subtasks.
    // Tap: auto-breakdown. Long press: opens an instructions sheet first.
    // No tooltip — Tooltip's long-press recognizer wins the gesture arena
    // over the outer GestureDetector, so we omit it here.
    final splitButton = GestureDetector(
      onLongPress: () => _showSplitWithInstructions(context, service),
      child: IconButton(
        icon: const Icon(Icons.call_split, size: 20),
        onPressed: () => _handleSplit(context, service),
      ),
    );

    if (isCurrent) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          splitButton,
          IconButton(
            icon: Icon(AppIcons.complete, color: AppColors.strong),
            tooltip: 'Mark complete',
            onPressed: () => service.completeCurrentSubTask(goal.goalId),
          ),
        ],
      );
    }

    // Pending but not current — locked until earlier subtasks complete.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        splitButton,
        Icon(Icons.lock_outline, size: 18, color: AppColors.muted),
        const SizedBox(width: 8),
      ],
    );
  }

  // Calls the configured decomposition provider to break this subtask into
  // 1–3 smaller steps. While in flight, the row is locked via _isBreakingDown
  // so the user can't edit/swipe/drag/complete the row out from under the
  // result. On failure or when no provider is configured, falls back to the
  // manual entry sheet.
  Future<void> _showSplitWithInstructions(
    BuildContext context,
    GoalService service,
  ) async {
    final decomp = context.read<GoalDecompositionService>();
    if (!decomp.canAutoBreakdown) {
      _showManualSplitSheet(context, service);
      return;
    }
    final instructions = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _InstructionsSheet(
        hint: 'e.g. keep each step under 5 minutes',
        confirmLabel: 'Break down',
      ),
    );
    if (instructions != null && mounted) {
      // ignore: use_build_context_synchronously
      _handleSplit(this.context, service, additionalInstructions: instructions);
    }
  }

  Future<void> _handleSplit(
    BuildContext context,
    GoalService service, {
    String? additionalInstructions,
  }) async {
    final decomp = context.read<GoalDecompositionService>();

    if (!decomp.canAutoBreakdown) {
      _showManualSplitSheet(context, service);
      return;
    }

    // Capture messenger before the await so we don't reach through context
    // after the widget is potentially disposed.
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isBreakingDown = true);

    final descriptions = await decomp.breakdownSubtask(
      subtask.description,
      additionalInstructions: additionalInstructions,
    );

    // If the widget was disposed mid-await (e.g. the goal got deleted),
    // bail out before touching state or the service.
    if (!mounted) return;

    if (descriptions == null) {
      setState(() => _isBreakingDown = false);
      messenger.showSnackBar(SnackBar(
        content: const Text("Couldn't break this down automatically"),
        action: SnackBarAction(
          label: 'Edit manually',
          onPressed: () {
            if (mounted) _showManualSplitSheet(this.context, service);
          },
        ),
      ));
      return;
    }

    // splitSubTask replaces this subtask in the list, so the widget is about
    // to be disposed by the parent rebuild. No need to clear _isBreakingDown.
    service.splitSubTask(goal.goalId, subtask.subtaskId, descriptions);
  }

  void _showManualSplitSheet(BuildContext context, GoalService service) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SubTaskSplitSheet(
        goalId: goal.goalId,
        subtask: subtask,
        goalService: service,
      ),
    );
  }

  void _showEditSheet(BuildContext context, GoalService service) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SubTaskSheet(
        goalId: goal.goalId,
        goalService: service,
        existingSubTask: subtask,
      ),
    );
  }

}
// --- Add / Edit subtask sheet ---
// Single sheet handles both modes — if existingSubTask is null, it's add mode

class _SubTaskSheet extends StatefulWidget {
  final String goalId;
  final GoalService goalService;
  final SubTask? existingSubTask; // null = add, non-null = edit

  const _SubTaskSheet({
    required this.goalId,
    required this.goalService,
    this.existingSubTask,
  });

  @override
  State<_SubTaskSheet> createState() => _SubTaskSheetState();
}

class _SubTaskSheetState extends State<_SubTaskSheet> {
  late final TextEditingController _controller;

  bool get _isEditing => widget.existingSubTask != null;

  @override
  void initState() {
    super.initState();
    // Pre-populate if editing — initState is the right place for this,
    // equivalent to initialising state from props in a React class component
    _controller = TextEditingController(
      text: widget.existingSubTask?.description ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    if (_isEditing) {
      widget.goalService.updateSubTaskDescription(
        widget.goalId,
        widget.existingSubTask!.subtaskId,
        text,
      );
    } else {
      widget.goalService.addSubTask(widget.goalId, text);
    }

    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AppBottomSheet(
      title: _isEditing ? 'Edit subtask' : 'New subtask',
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'What needs to be done?',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _submit,
          child: Text(_isEditing ? 'Save changes' : 'Add subtask'),
        ),
      ],
    );
  }
}

// --- Split subtask sheet ---

class _SubTaskSplitSheet extends StatefulWidget {
  final String goalId;
  final SubTask subtask;
  final GoalService goalService;

  const _SubTaskSplitSheet({
    required this.goalId,
    required this.subtask,
    required this.goalService,
  });

  @override
  State<_SubTaskSplitSheet> createState() => _SubTaskSplitSheetState();
}

class _SubTaskSplitSheetState extends State<_SubTaskSplitSheet> {
  late final TextEditingController _step1Controller;
  late final TextEditingController _step2Controller;

  @override
  void initState() {
    super.initState();
    // Pre-fill step 1 with the original so the user edits rather than rewrites
    _step1Controller = TextEditingController(text: widget.subtask.description);
    _step2Controller = TextEditingController();
  }

  @override
  void dispose() {
    _step1Controller.dispose();
    _step2Controller.dispose();
    super.dispose();
  }

  void _submit() {
    final step1 = _step1Controller.text.trim();
    final step2 = _step2Controller.text.trim();
    if (step1.isEmpty || step2.isEmpty) return;

    widget.goalService.splitSubTask(
      widget.goalId,
      widget.subtask.subtaskId,
      [step1, step2],
    );

    if (context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AppBottomSheet(
      title: 'Split into two steps',
      children: [
        // Show original as read-only context
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            widget.subtask.description,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _step1Controller,
          autofocus: true,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'First step',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _step2Controller,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Second step',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: const Text('Replace with these two steps'),
        ),
      ],
    );
  }
}

class _InboxReadyState extends StatelessWidget {
  final Goal goal;

  const _InboxReadyState({required this.goal});

  @override
  Widget build(BuildContext context) {
    final decomp = context.read<GoalDecompositionService>();

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 48, color: AppColors.muted),
          const SizedBox(height: 12),
          Text('In your inbox', style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 4),
          Text(
            decomp.canAutoBreakdown
                ? 'Generate subtasks when you\'re ready to turn this into an active goal, or add them manually.'
                : 'Add subtasks using the + button below to convert this into an active goal.',
            style: TextStyle(color: AppColors.muted),
            textAlign: TextAlign.center,
          ),
          if (decomp.canAutoBreakdown) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: const Icon(Icons.auto_awesome_outlined, size: 18),
              label: const Text('Generate subtasks'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 48),
              ),
              onPressed: () => _generate(context, decomp),
            ),
          ],
        ],
      ),
    );
  }

  void _generate(BuildContext context, GoalDecompositionService decomp) {
    final decompState = context.read<DecompositionState>();
    final goalService = context.read<GoalService>();
    unawaited(decomp.decomposeInBackground(
      goalId: goal.goalId,
      title: goal.title,
      description: goal.notes.isEmpty ? null : goal.notes,
      onResult: (descriptions) =>
          goalService.replaceAllSubTasks(goal.goalId, descriptions),
      state: decompState,
    ));
  }
}

class _RedecomposeDialog extends StatefulWidget {
  const _RedecomposeDialog();

  @override
  State<_RedecomposeDialog> createState() => _RedecomposeDialogState();
}

class _RedecomposeDialogState extends State<_RedecomposeDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Re-decompose subtasks?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'All current subtasks will be replaced with new AI-generated steps.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Additional instructions (optional)',
              hintText: 'e.g. focus on the research phase',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Re-decompose'),
        ),
      ],
    );
  }
}

class _InstructionsSheet extends StatefulWidget {
  final String hint;
  final String confirmLabel;

  const _InstructionsSheet({required this.hint, required this.confirmLabel});

  @override
  State<_InstructionsSheet> createState() => _InstructionsSheetState();
}

class _InstructionsSheetState extends State<_InstructionsSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppBottomSheet(
      title: 'Custom instructions',
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: widget.hint,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _DecomposingState extends StatelessWidget {
  const _DecomposingState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Generating subtasks…',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'This may take a moment',
            style: TextStyle(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _EmptySubtaskState extends StatelessWidget {
  const _EmptySubtaskState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(addSubtaskIcon, size: 48, color: AppColors.muted),
          const SizedBox(height: 12),
          Text('No subtasks yet', style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 4),
          Text(
            'Tap the button below to add your first step',
            style: TextStyle(color: AppColors.muted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
