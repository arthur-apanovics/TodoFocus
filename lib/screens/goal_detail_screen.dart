import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import '../models/goal.dart';
import '../models/sub_task.dart';
import '../services/goal_decomposition_service.dart';
import '../services/goal_repository.dart';
import '../services/goal_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import 'widgets/app_bottom_sheet.dart';

const addSubtaskIcon = Icons.playlist_add;

class GoalDetailScreen extends StatelessWidget {
  final String goalId;

  const GoalDetailScreen({super.key, required this.goalId});

  @override
  Widget build(BuildContext context) {
    // Watch the repository directly so we rebuild when any goal changes
    final repository = context.watch<GoalRepository>();
    final goal = repository.findById(goalId);

    // Guard against the goal being deleted while this screen is open
    if (goal == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.pop(context);
      });
      return const SizedBox.shrink();
    }

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
          // Reorderable subtask list
          goal.subtasks.isEmpty
              ? const SliverToBoxAdapter(child: _EmptySubtaskState())
              : SliverReorderableList(
                  itemCount: goal.subtasks.length,
                  onReorder: (oldIndex, newIndex) {
                    final service = context.read<GoalService>();
                    service.reorderSubTask(goalId, oldIndex, newIndex);
                  },
                  itemBuilder: (context, index) {
                    final subtask = goal.subtasks[index];
                    // ReorderableListView requires every item to have a Key
                    // ValueKey wraps a unique value — like React's key prop
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
      floatingActionButton: FloatingActionButton(
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
      builder: (_) => _SubTaskSheet(goalId: goalId, goalService: service),
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

    return PopupMenuButton<String>(
      onSelected: (value) {
        if (value == 'delete') _confirmDelete(context, service);
      },
      itemBuilder: (_) => [
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
          opacity: _isBreakingDown
              ? 0.6
              : (isCurrent || isCompleted)
                  ? 1.0
                  : 0.45,
          child: ListTile(
            // Drag handle — only for non-completed, non-breaking-down rows.
            leading: isCompleted
                // Same drag-handle silhouette as the other rows, just faded —
                // signals "this row exists in the list but can't be moved".
                // Reuses the shape so completed rows don't feel structurally
                // different from the rest.
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: Icon(Icons.drag_handle, color: AppColors.faded),
                  )
                : _isBreakingDown
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child:
                            Icon(Icons.drag_handle, color: AppColors.faded),
                      )
                    : ReorderableDragStartListener(
                        index: index,
                        child: const Icon(Icons.drag_handle),
                      ),
            title: GestureDetector(
              // Only allow editing current or pending subtasks, and not while
              // a breakdown is in flight for this row.
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
                    : null,
              ),
            ),
            subtitle: Text(_isBreakingDown
                ? 'Breaking down…'
                : _stateLabel(isCurrent, isCompleted)),
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
    // Primary path uses the configured LLM/Goblin provider to break this
    // subtask down further. Falls back to manual entry when no provider is set.
    final splitButton = IconButton(
      icon: const Icon(Icons.call_split, size: 20),
      tooltip: 'Break down further',
      onPressed: () => _handleSplit(context, service),
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
  Future<void> _handleSplit(BuildContext context, GoalService service) async {
    final decomp = context.read<GoalDecompositionService>();

    if (!decomp.canAutoBreakdown) {
      _showManualSplitSheet(context, service);
      return;
    }

    // Capture messenger before the await so we don't reach through context
    // after the widget is potentially disposed.
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isBreakingDown = true);

    final descriptions = await decomp.breakdownSubtask(subtask.description);

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

  String _stateLabel(bool isCurrent, bool isCompleted) {
    if (isCompleted) return 'Completed';
    if (isCurrent) return 'Current';
    return 'Queued';
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
