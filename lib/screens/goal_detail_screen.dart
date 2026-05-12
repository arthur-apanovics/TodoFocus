import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/goal.dart';
import '../models/sub_task.dart';
import '../services/goal_repository.dart';
import '../services/goal_service.dart';
import '../theme/app_colors.dart';
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
          decoration: const InputDecoration(
            labelText: 'Title',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notesController,
          maxLines: 3,
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
              service.removeGoal(goal.goalId);
              // Pop both the dialog and the detail screen
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// --- Subtask tile ---

class SubTaskTile extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final service = context.read<GoalService>();
    final isCurrent = goal.isCurrentSubTask(subtask);
    final isCompleted = subtask.isCompleted;
    final isPending = !isCompleted;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Dismissible(
        key: ValueKey(subtask.subtaskId),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 16),
          color: AppColors.destructive,
          child: Icon(Icons.delete_outline, color: AppColors.onDestructive),
        ),
        onDismissed: (_) =>
            service.deleteSubTask(goal.goalId, subtask.subtaskId),
        child: Opacity(
          opacity: (isCurrent || isCompleted) ? 1.0 : 0.45,
          child: ListTile(
            // Drag handle — only for non-completed subtasks
            leading: isCompleted
                // Same drag-handle silhouette as the other rows, just faded —
                // signals "this row exists in the list but can't be moved".
                // Reuses the shape so completed rows don't feel structurally
                // different from the rest.
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: Icon(Icons.drag_handle, color: AppColors.faded),
                  )
                : ReorderableDragStartListener(
                    index: index,
                    child: const Icon(Icons.drag_handle),
                  ),
            title: GestureDetector(
              // Only allow editing current or pending subtasks
              onTap: isPending ? () => _showEditSheet(context, service) : null,
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
            subtitle: Text(_stateLabel(isCurrent, isCompleted)),
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
    // Monotone palette — three semantic shades carry the meaning.
    // See AppColors for the actual values; tweak there to experiment.
    //   faded   → completed row leading icon
    //   muted   → lock, restore  (present but secondary)
    //   strong  → primary action (the current subtask's circle)
    if (isCompleted) {
      return IconButton(
        icon: Icon(Icons.restore, size: 20, color: AppColors.muted),
        tooltip: 'Mark incomplete',
        onPressed: () =>
            service.uncompleteSubTask(goal.goalId, subtask.subtaskId),
      );
    }

    if (isCurrent) {
      // Hollow circle is the universal "tap to check off" affordance.
      // Strongest shade gives it visual weight without breaking monotone.
      return IconButton(
        icon: Icon(Icons.radio_button_unchecked, color: AppColors.strong),
        tooltip: 'Mark complete',
        onPressed: () => service.completeCurrentSubTask(goal.goalId),
      );
    }

    // Pending but not current — locked until earlier subtasks complete.
    return Icon(Icons.lock_outline, size: 18, color: AppColors.muted);
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
