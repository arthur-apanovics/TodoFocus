import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import '../models/enums.dart';
import '../models/goal.dart';
import '../models/sub_task.dart';
import '../services/decomposition_state.dart';
import '../services/draft_service.dart';
import '../services/focus_list_service.dart' show FocusListService;
import '../services/goal_decomposition_service.dart';
import '../services/goal_repository.dart';
import '../services/goal_service.dart';
import '../services/settings/llm_settings_service.dart';
import '../theme/app_icons.dart';
import '../theme/app_palette.dart';
import 'widgets/app_bottom_sheet.dart';
import 'widgets/auto_sleep_picker_sheet.dart';
import 'widgets/emoji_picker_sheet.dart';
import 'widgets/snooze_picker_sheet.dart';
import 'widgets/goal_symbol.dart';
import 'widgets/recurrence_picker_sheet.dart';

// Unified goal screen — handles inbox, active, and completed goals. Replaces
// the separate active/planning split with a single screen whose bottom bar,
// generation card visibility, completion controls, and overflow menu vary by
// goal.status. The triggerBreakdown flag fires an LLM breakdown on arrival
// (used by the "Break it down" notification action).
class GoalPlanningScreen extends StatefulWidget {
  final String goalId;
  final bool triggerBreakdown;

  const GoalPlanningScreen({
    super.key,
    required this.goalId,
    this.triggerBreakdown = false,
  });

  @override
  State<GoalPlanningScreen> createState() => _GoalPlanningScreenState();
}

enum _GoalAction { archive, delete, sendToPlanning }

class _GoalPlanningScreenState extends State<GoalPlanningScreen> {
  late final DecompositionState _decompositionState;
  late final GoalRepository _repo;

  // Multi-level undo stack. Each entry is a JSON snapshot of the goal taken
  // *before* an action mutated it — so popping restores the pre-action state.
  // [_lastSeenJson] holds the goal's current persisted state so we can diff
  // against it when the repo emits a change. Both are discarded on dispose,
  // which is the implicit "commit" point (back arrow or "Queue Goal").
  final List<String> _undoStack = [];
  String? _lastSeenJson;

  // Goal-completion celebration: when the goal transitions from active to
  // completed while the user is on this screen (final subtask ticked off
  // here), pop back with a snackbar. Don't celebrate if the user navigated
  // *into* an already-completed goal — that should render normally.
  bool _wasActive = false;
  bool _completionAnnounced = false;

  @override
  void initState() {
    super.initState();
    _decompositionState = context.read<DecompositionState>();
    _decompositionState.addListener(_onDecompositionChanged);

    _repo = context.read<GoalRepository>();
    final goal = _repo.findById(widget.goalId);
    if (goal != null) {
      _lastSeenJson = jsonEncode(goal.toJson());
      _wasActive = goal.status == GoalStatus.active;
    }
    _repo.addListener(_onRepoChanged);

    if (widget.triggerBreakdown) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _autoBreakdown();
      });
    }
  }

  @override
  void dispose() {
    _decompositionState.removeListener(_onDecompositionChanged);
    _repo.removeListener(_onRepoChanged);
    super.dispose();
  }

  // Fires whenever GoalRepository.save() is called from anywhere — manual
  // edits, LLM generation, drag-reorders, etc. We diff the live goal's JSON
  // against the last snapshot we saw; any real change pushes the previous
  // state onto the undo stack. No setState needed here: the same notifier
  // already triggers a rebuild via context.watch<GoalRepository>() in build.
  void _onRepoChanged() {
    if (!mounted) return;
    final goal = _repo.findById(widget.goalId);
    if (goal == null) return;
    final currentJson = jsonEncode(goal.toJson());
    if (_lastSeenJson != currentJson) {
      if (_lastSeenJson != null) _undoStack.add(_lastSeenJson!);
      _lastSeenJson = currentJson;
    }
  }

  void _onDecompositionChanged() {
    if (!mounted) return;
    if (_decompositionState.hasFallback(widget.goalId)) {
      final error = _decompositionState.fallbackError(widget.goalId);
      _decompositionState.clearFallback(widget.goalId);
      final debugMode = context.read<LlmSettingsService>().debugMode;
      final message = debugMode && error != null
          ? error
          : 'AI unavailable — template subtasks used instead';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
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
    if (!mounted) return;

    if (descriptions == null) {
      _showManualSplit(subtask, service);
      return;
    }

    service.splitSubTask(widget.goalId, subtask.subtaskId, descriptions);
  }

  Future<void> _modifySubtasks(Goal goal, {String? instructions}) async {
    final decomp = context.read<GoalDecompositionService>();
    final decompState = context.read<DecompositionState>();
    final service = context.read<GoalService>();
    final messenger = ScaffoldMessenger.of(context);
    final debugMode = context.read<LlmSettingsService>().debugMode;

    final pendingSteps = goal.subtasks
        .where((t) => t.state == SubTaskState.pending)
        .map((t) => t.description)
        .toList();

    final completedSteps = goal.subtasks
        .where((t) => t.state == SubTaskState.completed)
        .map((t) => t.description)
        .toList();

    Object? llmError;
    decompState.begin(goal.goalId);
    try {
      final descriptions = await decomp.modifySubtasks(
        goal.title,
        description: goal.notes.isEmpty ? null : goal.notes,
        additionalInstructions: instructions,
        difficulty: goal.difficulty,
        pendingSteps: pendingSteps,
        completedSteps: completedSteps.isEmpty ? null : completedSteps,
        onError: (e) => llmError = e,
      );
      if (!mounted) return;
      if (descriptions == null) {
        messenger.showSnackBar(SnackBar(
          content: Text(debugMode && llmError != null
              ? llmError.toString()
              : "Couldn't modify subtasks"),
        ));
        return;
      }
      // Modify never touches completed steps — replace only pending ones.
      service.replacePendingSubTasks(goal.goalId, descriptions);
    } finally {
      if (mounted) decompState.end(goal.goalId);
    }
  }

  Future<void> _generateSubtasks(
    Goal goal, {
    String? instructions,
    bool regenerateAll = false,
  }) async {
    final decomp = context.read<GoalDecompositionService>();
    final decompState = context.read<DecompositionState>();
    final service = context.read<GoalService>();
    final messenger = ScaffoldMessenger.of(context);
    final debugMode = context.read<LlmSettingsService>().debugMode;

    final completedSteps = goal.subtasks
        .where((t) => t.state == SubTaskState.completed)
        .map((t) => t.description)
        .toList();
    final preserveCompleted = !regenerateAll && completedSteps.isNotEmpty;

    Object? llmError;
    decompState.begin(goal.goalId);
    try {
      final descriptions = await decomp.redecomposeSubtasks(
        goal.title,
        description: goal.notes.isEmpty ? null : goal.notes,
        additionalInstructions: instructions,
        difficulty: goal.difficulty,
        completedSteps: preserveCompleted ? completedSteps : null,
        onError: (e) => llmError = e,
      );
      if (!mounted) return;
      if (descriptions == null) {
        messenger.showSnackBar(SnackBar(
          content: Text(debugMode && llmError != null
              ? llmError.toString()
              : goal.subtasks.isEmpty
                  ? "Couldn't generate subtasks"
                  : "Couldn't regenerate subtasks"),
        ));
        return;
      }
      if (preserveCompleted) {
        service.replacePendingSubTasks(goal.goalId, descriptions);
      } else {
        service.replaceAllSubTasks(goal.goalId, descriptions);
      }
    } finally {
      if (mounted) decompState.end(goal.goalId);
    }
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
    final repository = context.watch<GoalRepository>();
    final goal = repository.findById(widget.goalId);

    if (goal == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.pop(context);
      });
      return const SizedBox.shrink();
    }

    final isGenerating = context.watch<DecompositionState>().isDecomposing(
      widget.goalId,
    );
    final llmEnabled =
        context.watch<LlmSettingsService>().buildClient() != null;

    final isInbox = goal.status == GoalStatus.inbox;
    final isActive = goal.status == GoalStatus.active;
    final isCompleted = goal.status == GoalStatus.completed;
    final isEditable = !isCompleted;

    // Goal just transitioned to completed while on this screen — celebrate
    // and pop back once. The _wasActive guard prevents the snackbar from
    // firing when the user navigates *into* an already-completed goal.
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
    if (isCompleted && _wasActive && _completionAnnounced) {
      // Suppress rendering during the async pop frame to avoid a flash.
      return const SizedBox.shrink();
    }

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        // Tapping the title opens the edit sheet, mirroring the tappable
        // description below. Read-only when the goal is completed.
        title: isEditable
            ? Tooltip(
                message: 'Tap to edit title',
                child: GestureDetector(
                  onTap: () => _showEditGoalSheet(context, goal),
                  child: _AppBarTitle(goal: goal),
                ),
              )
            : _AppBarTitle(goal: goal),
        actions: [
          if (isEditable)
            IconButton(
              icon: const Icon(Icons.undo),
              // Tooltip includes the depth so the user has some idea how far
              // back undo will go without surfacing a full history UI.
              tooltip: _undoStack.isEmpty
                  ? 'Nothing to undo'
                  : 'Undo (${_undoStack.length})',
              onPressed: _undoStack.isEmpty ? null : _undo,
            ),
          // Planning (inbox) goals haven't been committed to — deleting
          // them outright is cleaner than archiving an unstarted plan.
          if (isInbox)
            PopupMenuButton<_GoalAction>(
              onSelected: (a) => _handleMenuAction(context, goal, a),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _GoalAction.delete,
                  child: ListTile(
                    leading: Icon(AppIcons.delete,
                        color: context.palette.destructive),
                    title: Text('Delete',
                        style:
                            TextStyle(color: context.palette.destructive)),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          if (isActive)
            PopupMenuButton<_GoalAction>(
              onSelected: (a) => _handleMenuAction(context, goal, a),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _GoalAction.archive,
                  child: ListTile(
                    leading: Icon(Icons.archive_outlined),
                    title: Text('Archive'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          if (isCompleted)
            PopupMenuButton<_GoalAction>(
              onSelected: (a) => _handleMenuAction(context, goal, a),
              itemBuilder: (_) => const [
                PopupMenuItem(
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
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _GoalDescriptionCard(
              goal: goal,
              onEdit: isEditable
                  ? () => _showEditGoalSheet(
                        context,
                        goal,
                        autofocusDescription: true,
                      )
                  : null,
            ),
          ),
          if (llmEnabled && isEditable)
            SliverToBoxAdapter(
              child: _GenerationCard(
                goal: goal,
                isGenerating: isGenerating,
                onModify: ({instructions}) =>
                    _modifySubtasks(goal, instructions: instructions),
                onRegenerate: ({instructions, regenerateAll = false}) =>
                    _generateSubtasks(
                      goal,
                      instructions: instructions,
                      regenerateAll: regenerateAll,
                    ),
              ),
            ),
          // Small breathing room between the header block and the subtask list.
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          if (isGenerating)
            const SliverToBoxAdapter(child: _DecomposingState())
          else if (isInbox && goal.subtasks.isEmpty)
            SliverToBoxAdapter(child: _InboxReadyState(goal: goal))
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
                // Pending subtasks of editable goals are draggable. Completed
                // subtasks never are; completed goals are fully read-only.
                final draggable = isEditable &&
                    subtask.state == SubTaskState.pending;
                return ReorderableDelayedDragStartListener(
                  key: ValueKey(subtask.subtaskId),
                  index: index,
                  enabled: draggable,
                  child: SubTaskTile(
                    subtask: subtask,
                    goal: goal,
                    // Active goals → full completion controls. Inbox →
                    // breakdown only (no completion in planning mode).
                    // Completed → read-only, no completion or breakdown.
                    showCompletion: isActive,
                    readOnly: isCompleted,
                  ),
                );
              },
            ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(context, goal),
      floatingActionButton: !isEditable || isGenerating
          ? null
          : llmEnabled
              ? _SpeedDial(
                  onAddManual: () => _showAddSubTaskSheet(context),
                  onAddWithAI: () => _showAddWithAISheet(context),
                )
              : FloatingActionButton(
                  onPressed: () => _showAddSubTaskSheet(context),
                  tooltip: 'Add subtask',
                  child: const Icon(AppIcons.addSubtask),
                ),
    );
  }

  void _handleMenuAction(
    BuildContext context,
    Goal goal,
    _GoalAction action,
  ) {
    final service = context.read<GoalService>();
    switch (action) {
      case _GoalAction.archive:
        _confirmArchive(context, service);
      case _GoalAction.delete:
        _confirmDelete(context, service);
      case _GoalAction.sendToPlanning:
        service.sendToPlanning(goal.goalId);
        Navigator.pop(context);
    }
  }

  /// Bottom bar varies by goal status:
  ///   • inbox     → "Queue Goal" (commits the plan, moves to active)
  ///   • active    → focus-bar (toggle the whole goal in/out of today)
  ///   • completed → no bar (goal is done, no actions)
  Widget? _buildBottomBar(BuildContext context, Goal goal) {
    switch (goal.status) {
      case GoalStatus.inbox:
        return _QueueGoalBar(goal: goal);
      case GoalStatus.active:
        return _FocusBar(goal: goal);
      case GoalStatus.completed:
      case GoalStatus.archived:
        return null;
    }
  }

  void _showEditGoalSheet(
    BuildContext context,
    Goal goal, {
    bool autofocusDescription = false,
  }) {
    final service = context.read<GoalService>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _GoalEditSheet(
        goal: goal,
        goalService: service,
        autofocusDescription: autofocusDescription,
      ),
    );
  }

  void _showAddSubTaskSheet(BuildContext context) {
    final service = context.read<GoalService>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          _SubTaskSheet(goalId: widget.goalId, goalService: service),
    );
  }

  Future<void> _showAddWithAISheet(BuildContext context) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _PromptSheet(
        title: 'Add steps with AI',
        hint: 'e.g. add a step to review my notes',
        confirmLabel: 'Add steps',
      ),
    );
    if (result == null || !mounted) return;

    final repo = context.read<GoalRepository>();
    final goal = repo.findById(widget.goalId);
    if (goal == null) return;

    // ignore: use_build_context_synchronously
    await _handleAddWithAI(this.context, goal, prompt: result.isEmpty ? null : result);
  }

  Future<void> _handleAddWithAI(
    BuildContext context,
    Goal goal, {
    String? prompt,
  }) async {
    final decomp = context.read<GoalDecompositionService>();
    final service = context.read<GoalService>();
    final messenger = ScaffoldMessenger.of(context);
    final debugMode = context.read<LlmSettingsService>().debugMode;
    final decompState = context.read<DecompositionState>();

    final existingPending = goal.subtasks
        .where((t) => t.state == SubTaskState.pending)
        .map((t) => t.description)
        .toList();
    final existingCompleted = goal.subtasks
        .where((t) => t.state == SubTaskState.completed)
        .map((t) => t.description)
        .toList();

    Object? llmError;
    decompState.begin(goal.goalId);
    try {
      final descriptions = await decomp.addSubtasksFromPrompt(
        goal.title,
        description: goal.notes.isEmpty ? null : goal.notes,
        userPrompt: prompt,
        difficulty: goal.difficulty,
        existingPendingSteps: existingPending.isNotEmpty ? existingPending : null,
        existingCompletedSteps:
            existingCompleted.isNotEmpty ? existingCompleted : null,
        onError: (e) => llmError = e,
      );
      if (!mounted) return;
      if (descriptions == null) {
        messenger.showSnackBar(SnackBar(
          content: Text(debugMode && llmError != null
              ? llmError.toString()
              : "Couldn't generate new steps"),
        ));
        return;
      }
      service.appendSubTasks(goal.goalId, descriptions);
    } finally {
      if (mounted) decompState.end(goal.goalId);
    }
  }

  // Reverts the goal to the state immediately before the most recent action.
  // No confirmation: each undo only rolls back a single step, matching the
  // behaviour of native undo affordances in other apps. Repeated taps walk
  // further back through the history; once the stack is empty the AppBar
  // button is disabled.
  //
  // We update _lastSeenJson *before* calling repo.save() so the listener
  // that fires after notifyListeners() sees the new state as already-known
  // and doesn't push the post-undo state back onto the stack.
  void _undo() {
    if (_undoStack.isEmpty) return;
    final previousJson = _undoStack.removeLast();
    _lastSeenJson = previousJson;
    final restored = Goal.fromJson(
      jsonDecode(previousJson) as Map<String, dynamic>,
    );
    _repo.save(restored);
  }

  Future<void> _confirmArchive(
    BuildContext context,
    GoalService service,
  ) async {
    final repo = context.read<GoalRepository>();
    final goal = repo.findById(widget.goalId);
    if (goal == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Archive goal?'),
        content: const Text(
          'The goal will be moved to your completed archive.',
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
    if (confirmed == true && context.mounted) {
      service.archiveGoal(goal.goalId);
      Navigator.pop(context);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    GoalService service,
  ) async {
    final repo = context.read<GoalRepository>();
    final goal = repo.findById(widget.goalId);
    if (goal == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete goal?'),
        content: const Text(
          'This goal and its plan will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.palette.destructive,
              foregroundColor: context.palette.onDestructive,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      service.removeGoal(goal.goalId);
      Navigator.pop(context);
    }
  }
}

// --- AI generation card (collapsible) ---

class _GenerationCard extends StatefulWidget {
  final Goal goal;
  final bool isGenerating;
  final Future<void> Function({String? instructions}) onModify;
  final Future<void> Function({String? instructions, bool regenerateAll})
  onRegenerate;

  const _GenerationCard({
    required this.goal,
    required this.isGenerating,
    required this.onModify,
    required this.onRegenerate,
  });

  @override
  State<_GenerationCard> createState() => _GenerationCardState();
}

class _GenerationCardState extends State<_GenerationCard> {
  final _expansionController = ExpansibleController();
  late final DraftService _draftService;
  late final TextEditingController _instructionsController;
  // Only relevant for regenerate when there are completed steps.
  bool _regenerateAll = false;

  bool get _isEmpty => widget.goal.subtasks.isEmpty;

  int get _completedCount => widget.goal.subtasks
      .where((t) => t.state == SubTaskState.completed)
      .length;

  @override
  void initState() {
    super.initState();
    _draftService = context.read<DraftService>();
    _instructionsController = TextEditingController(
      text: _draftService.redecomposeInstructions(widget.goal.goalId),
    );
    // Persist on every keystroke — draft survives navigation and widget rebuilds.
    _instructionsController.addListener(_saveInstructionsDraft);
  }

  void _saveInstructionsDraft() {
    _draftService.saveRedecomposeInstructions(
      widget.goal.goalId,
      _instructionsController.text,
    );
  }

  @override
  void dispose() {
    _instructionsController.dispose();
    super.dispose();
  }

  String? get _instructions {
    final t = _instructionsController.text.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _handleModify() async {
    _expansionController.collapse();
    await widget.onModify(instructions: _instructions);
  }

  Future<void> _handleRegenerate() async {
    _expansionController.collapse();
    await widget.onRegenerate(
      instructions: _instructions,
      regenerateAll: _regenerateAll,
    );
    if (mounted) setState(() => _regenerateAll = false);
  }

  @override
  Widget build(BuildContext context) {
    final hasCompleted = _completedCount > 0;

    // Same surface colour as the AppBar and _GoalDescriptionCard so this
    // reads as one continuous block. The border on the ExpansionTile is
    // suppressed (known Flutter artifact); a Divider at the bottom separates
    // the whole header region from the subtask list below.
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExpansionTile(
            controller: _expansionController,
            // Start expanded for empty goals (first-time planning), collapsed when
            // subtasks already exist so the list is the primary focus.
            initiallyExpanded: _isEmpty,
            // Suppress the 1 px top/bottom border Flutter adds when expanded.
            shape: const Border(),
            collapsedShape: const Border(),
            leading: widget.isGenerating
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(AppIcons.aiGenerate),
            title: Text(_isEmpty ? 'Generate subtasks' : 'AI generation'),
            children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DifficultyRow(goal: widget.goal),
                const SizedBox(height: 16),
                TextField(
                  controller: _instructionsController,
                  enabled: !widget.isGenerating,
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Additional instructions (optional)',
                    hintText: 'e.g. focus on the research phase',
                    border: OutlineInputBorder(),
                  ),
                ),
                // Compact "regenerate everything" checkbox — only shown when
                // there are completed steps and subtasks already exist.
                if (!_isEmpty && hasCompleted) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: _regenerateAll,
                          visualDensity: VisualDensity.compact,
                          onChanged: widget.isGenerating
                              ? null
                              : (v) =>
                                  setState(() => _regenerateAll = v ?? false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: widget.isGenerating
                            ? null
                            : () => setState(
                                () => _regenerateAll = !_regenerateAll),
                        child: Text(
                          'Replace completed steps too',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                if (_isEmpty)
                  // No subtasks yet — single "Generate" button.
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed:
                          widget.isGenerating ? null : _handleRegenerate,
                      icon: widget.isGenerating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(AppIcons.aiGenerate),
                      label: const Text('Generate steps'),
                    ),
                  )
                else
                  // Subtasks exist — split button: Modify (left) + Regenerate (right).
                  _SplitModifyButton(
                    isGenerating: widget.isGenerating,
                    onModify: _handleModify,
                    onRegenerate: _handleRegenerate,
                  ),
              ],
            ),
          ),
        ],
      ),
          const Divider(height: 1, thickness: 1),
        ],
      ),
    );
  }
}

// --- Split modify / regenerate button ---
//
// Left half  → Modify     (edits the existing pending steps in-place)
// Right half → Regenerate (starts fresh — always visible so both actions are
//                          discoverable without requiring a long press)
//
// The two halves share the primary fill colour and are separated by a 1 px
// tinted divider, rendering as a single visual unit (standard split-button
// pattern). A tooltip on the regenerate half labels the icon for new users.

class _SplitModifyButton extends StatelessWidget {
  final bool isGenerating;
  final VoidCallback onModify;
  final VoidCallback onRegenerate;

  const _SplitModifyButton({
    required this.isGenerating,
    required this.onModify,
    required this.onRegenerate,
  });

  static const _height = 44.0;
  static const _innerRadius = Radius.zero;
  static const _outerRadius = Radius.circular(12);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: _height,
      child: Row(
        children: [
          // ── Primary action ───────────────────────────────────────────────
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.horizontal(
                    left: _outerRadius,
                    right: _innerRadius,
                  ),
                ),
                minimumSize: const Size(0, _height),
              ),
              onPressed: isGenerating ? null : onModify,
              icon: isGenerating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(AppIcons.aiGenerate, size: 18),
              label: const Text('Modify'),
            ),
          ),
          // ── Separator ────────────────────────────────────────────────────
          // Sits between two same-colour surfaces, reads as an inset rule.
          Container(
            width: 1,
            color: cs.onPrimary.withValues(alpha: 0.30),
          ),
          // ── Secondary action ─────────────────────────────────────────────
          Tooltip(
            message: 'Regenerate steps',
            child: FilledButton(
              style: FilledButton.styleFrom(
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.horizontal(
                    left: _innerRadius,
                    right: _outerRadius,
                  ),
                ),
                minimumSize: const Size(52, _height),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              onPressed: isGenerating ? null : onRegenerate,
              child: const Icon(Icons.autorenew, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Speed dial FAB ---
//
// Shown on the planning screen when an LLM is configured. Tapping the main
// button reveals two labelled mini-FABs:
//   • Add with AI  — user types a prompt; AI appends matching steps
//   • Add manually — existing manual subtask entry sheet
//
// When no LLM is configured the speed dial is not used and the plain FAB
// is rendered instead.

class _SpeedDial extends StatefulWidget {
  final VoidCallback onAddManual;
  final VoidCallback onAddWithAI;

  const _SpeedDial({required this.onAddManual, required this.onAddWithAI});

  @override
  State<_SpeedDial> createState() => _SpeedDialState();
}

class _SpeedDialState extends State<_SpeedDial> {
  bool _open = false;

  void _toggle() => setState(() => _open = !_open);

  void _closeAndRun(VoidCallback action) {
    setState(() => _open = false);
    action();
  }

  @override
  Widget build(BuildContext context) {
    // IntrinsicWidth forces the Column to be exactly as wide as its widest
    // child (the label+mini-FAB rows) rather than expanding to screen width,
    // which is what happens in the FAB slot's unbounded layout environment.
    return IntrinsicWidth(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // AnimatedSize shrinks/grows from the bottom-right so items slide
          // in from just above the FAB rather than from the top of the screen.
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: Alignment.bottomRight,
            child: AnimatedOpacity(
              opacity: _open ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: _open
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _SpeedDialItem(
                          icon: const Icon(AppIcons.aiGenerate),
                          label: 'Add with AI',
                          heroTag: 'speed_dial_ai',
                          onTap: () => _closeAndRun(widget.onAddWithAI),
                        ),
                        const SizedBox(height: 12),
                        _SpeedDialItem(
                          icon: const Icon(AppIcons.addSubtask),
                          label: 'Add manually',
                          heroTag: 'speed_dial_manual',
                          onTap: () => _closeAndRun(widget.onAddManual),
                        ),
                        const SizedBox(height: 16),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          FloatingActionButton(
            onPressed: _toggle,
            tooltip: _open ? 'Close' : 'Add subtask',
            child: AnimatedRotation(
              turns: _open ? 0.125 : 0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: const Icon(Icons.add),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeedDialItem extends StatelessWidget {
  final Widget icon;
  final String label;
  final String heroTag;
  final VoidCallback onTap;

  const _SpeedDialItem({
    required this.icon,
    required this.label,
    required this.heroTag,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: cs.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              label,
              style: TextStyle(
                color: cs.onSecondaryContainer,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        FloatingActionButton.small(
          heroTag: heroTag,
          onPressed: onTap,
          child: icon,
        ),
      ],
    );
  }
}

// --- Simple prompt sheet ---
//
// A minimal text-input bottom sheet that returns the trimmed user input.
// Used by the "Add with AI" flow where no granularity control is needed —
// the user describes what to add and the LLM decides on count.

class _PromptSheet extends StatefulWidget {
  final String title;
  final String hint;
  final String confirmLabel;

  const _PromptSheet({
    required this.title,
    required this.hint,
    required this.confirmLabel,
  });

  @override
  State<_PromptSheet> createState() => _PromptSheetState();
}

class _PromptSheetState extends State<_PromptSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _controller.text.trim().isNotEmpty;
    return AppBottomSheet(
      title: widget.title,
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onSubmitted: hasText
              ? (_) => Navigator.pop(context, _controller.text.trim())
              : null,
          decoration: InputDecoration(
            hintText: widget.hint,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: hasText
              ? () => Navigator.pop(context, _controller.text.trim())
              : null,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

// --- Goal description card ---

class _GoalDescriptionCard extends StatelessWidget {
  final Goal goal;
  // Null when the goal is read-only (completed) — the description still
  // renders, but tapping doesn't open the edit sheet.
  final VoidCallback? onEdit;

  const _GoalDescriptionCard({required this.goal, this.onEdit});

  @override
  Widget build(BuildContext context) {
    // Flush container — same surface color as the AppBar so they read as one
    // continuous region. A bottom divider separates it from the cards below.
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Notes / description (tap to edit). The placeholder only
                // shows for editable goals — completed goals with no notes
                // render nothing rather than offering a stale "tap to add".
                if (goal.notes.isNotEmpty)
                  GestureDetector(
                    onTap: onEdit,
                    child: Text(
                      goal.notes,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                else if (onEdit != null)
                  GestureDetector(
                    onTap: onEdit,
                    child: Text(
                      'Tap to add a description…',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                    ),
                  ),
                if (goal.subtasks.isNotEmpty) ...[
                  const SizedBox(height: 12),
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
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _DueDateChip(goal: goal),
                    _RecurrenceChip(goal: goal),
                  ],
                ),
                _GoalMetaLine(goal: goal),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1),
        ],
      ),
    );
  }
}

// --- Goal metadata line ---

/// Subtle one-line goal metadata under the description — creation and
/// completion dates. Renders nothing when neither is known (e.g. a legacy
/// goal saved before the createdAt field existed).
class _GoalMetaLine extends StatelessWidget {
  final Goal goal;

  const _GoalMetaLine({required this.goal});

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _format(DateTime d) {
    final label = '${d.day} ${_months[d.month - 1]}';
    return d.year == DateTime.now().year ? label : '$label ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    final created = goal.createdAt;
    if (created != null) parts.add('Created ${_format(created)}');
    final completed = goal.completedAt;
    if (completed != null) parts.add('Completed ${_format(completed)}');
    if (parts.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        parts.join('   ·   '),
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: context.palette.muted),
      ),
    );
  }
}

// --- Recurrence chip ---
//
// Mirrors [_DueDateChip] in shape and interaction: tap to edit, X to clear.
// Lives next to the due-date chip on the goal header so the user can see
// and configure both "when is this due" and "does this repeat" together.

class _RecurrenceChip extends StatelessWidget {
  final Goal goal;

  const _RecurrenceChip({required this.goal});

  Future<void> _open(BuildContext context) async {
    // Capture the service and goal id *before* awaiting the sheet. After the
    // bottom sheet pops, `context.mounted` may briefly read false (the
    // ancestor route is settling) — guarding on it would silently drop the
    // user's apply. Pulling the service eagerly means we can still write
    // even if the chip element rebuilt while the picker was open.
    final svc = context.read<GoalService>();
    final goalId = goal.goalId;
    final initial = goal.recurrence;

    final result = await RecurrencePickerSheet.show(context, initial: initial);
    if (result == null) return; // user cancelled

    if (result.cleared) {
      svc.setRecurrence(goalId, null);
      return;
    }
    final picked = result.recurrence;
    if (picked != null) {
      svc.setRecurrence(goalId, picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recurrence = goal.recurrence;
    if (recurrence == null) {
      return ActionChip(
        avatar: Icon(Icons.repeat, size: 14, color: context.palette.muted),
        label:
            Text('Repeat', style: TextStyle(color: context.palette.muted)),
        side: BorderSide.none,
        backgroundColor: Colors.transparent,
        onPressed: () => _open(context),
      );
    }
    return InputChip(
      avatar: Icon(Icons.repeat, size: 14, color: context.palette.accent),
      label: Text(recurrence.label),
      onPressed: () => _open(context),
      onDeleted: () =>
          context.read<GoalService>().setRecurrence(goal.goalId, null),
      deleteIcon: const Icon(Icons.close, size: 14),
      deleteButtonTooltipMessage: 'Remove recurrence',
    );
  }
}

// --- Goal menu (delete) ---

class _GoalEditSheet extends StatefulWidget {
  final Goal goal;
  final GoalService goalService;
  final bool autofocusDescription;

  const _GoalEditSheet({
    required this.goal,
    required this.goalService,
    this.autofocusDescription = false,
  });

  @override
  State<_GoalEditSheet> createState() => _GoalEditSheetState();
}

class _GoalEditSheetState extends State<_GoalEditSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  final _notesFocus = FocusNode();
  String? _emoji;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.goal.title);
    _notesController = TextEditingController(text: widget.goal.notes);
    _emoji = widget.goal.emoji;
    if (widget.autofocusDescription) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _notesFocus.requestFocus();
      });
    }
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
    if (_emoji != null) {
      widget.goalService.setEmoji(widget.goal.goalId, _emoji!);
    } else {
      widget.goalService.clearEmoji(widget.goal.goalId);
    }

    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _pickEmoji() async {
    final picked = await showEmojiPickerSheet(context);
    if (picked != null && mounted) setState(() => _emoji = picked);
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
        _EmojiRow(
          emoji: _emoji,
          onPick: _pickEmoji,
          onClear: () => setState(() {
            _emoji = null;
          }),
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: _submit, child: const Text('Save changes')),
      ],
    );
  }
}

// --- Difficulty row ---

class _DifficultyRow extends StatelessWidget {
  final Goal goal;

  const _DifficultyRow({required this.goal});

  @override
  Widget build(BuildContext context) {
    final service = context.read<GoalService>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How difficult is this goal to achieve?',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<GoalDifficulty>(
            segments: GoalDifficulty.values
                .map((d) => ButtonSegment(value: d, label: Text(d.displayName)))
                .toList(),
            selected: {goal.difficulty},
            onSelectionChanged: (s) =>
                service.updateGoal(goal.goalId, difficulty: s.first),
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
          ),
        ),
      ],
    );
  }
}

// --- Emoji row ---

/// Reusable emoji selector row used in both new-goal and edit-goal sheets.
class _EmojiRow extends StatelessWidget {
  final String? emoji;
  final VoidCallback onPick;
  final VoidCallback onClear;

  const _EmojiRow({
    required this.emoji,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        GestureDetector(
          onTap: onPick,
          child: Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(12),
            ),
            child: emoji != null
                ? GoalSymbol(name: emoji, size: 28)
                : Icon(Icons.add_reaction_outlined, color: cs.onSurfaceVariant),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            emoji != null ? 'Tap to change icon' : 'Add an icon (optional)',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        if (emoji != null)
          IconButton(
            icon: const Icon(Icons.clear, size: 18),
            tooltip: 'Remove emoji',
            onPressed: onClear,
          ),
      ],
    );
  }
}

// --- Due date chip ---

class _DueDateChip extends StatelessWidget {
  final Goal goal;

  const _DueDateChip({required this.goal});

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _format(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(d.year, d.month, d.day);
    final diff = date.difference(today).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff == -1) return 'Yesterday';
    if (diff < 0) return '${diff.abs()}d overdue';
    if (diff <= 7) return 'In ${diff}d';
    final label = '${_months[d.month - 1]} ${d.day}';
    return d.year == now.year ? label : '$label ${d.year}';
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: goal.dueDate != null && !goal.dueDate!.isBefore(today)
          ? goal.dueDate!
          : today,
      firstDate: today,
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null && context.mounted) {
      context.read<GoalService>().setDueDate(goal.goalId, picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = goal.dueDate;
    if (date == null) {
      return ActionChip(
        avatar: Icon(
          Icons.calendar_today_outlined,
          size: 14,
          color: context.palette.muted,
        ),
        label: Text('Add date',
            style: TextStyle(color: context.palette.muted)),
        side: BorderSide.none,
        backgroundColor: Colors.transparent,
        onPressed: () => _pickDate(context),
      );
    }
    return InputChip(
      avatar: const Icon(Icons.calendar_today_outlined, size: 14),
      label: Text(_format(date)),
      onPressed: () => _pickDate(context),
      onDeleted: () =>
          context.read<GoalService>().setDueDate(goal.goalId, null),
      deleteIcon: const Icon(Icons.close, size: 14),
      deleteButtonTooltipMessage: 'Remove date',
    );
  }
}

// --- Subtask tile ---

class SubTaskTile extends StatefulWidget {
  final SubTask subtask;
  final Goal goal; // need the parent goal to check isCurrentSubTask
  // When false, the trailing complete/uncomplete icons are hidden so the
  // tile reads as planning-only (split + slide-to-delete remain).
  //   • inbox  → showCompletion: false (no completion in planning)
  //   • active → showCompletion: true  (current step has complete circle)
  final bool showCompletion;
  // When true, the tile is fully read-only: no edit-tap, no swipe-delete,
  // no breakdown, no completion controls. Set for completed goals.
  final bool readOnly;

  const SubTaskTile({
    super.key,
    required this.subtask,
    required this.goal,
    this.showCompletion = true,
    this.readOnly = false,
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

  @override
  Widget build(BuildContext context) {
    final service = context.read<GoalService>();
    final isCurrent = goal.isCurrentSubTask(subtask);
    final isCompleted = subtask.isCompleted;
    final stepNumber = goal.subtasks.indexOf(subtask) + 1;

    // Slidable instead of Dismissible:
    //  - Doesn't try to auto-remove the row, so it never collides with the
    //    Provider rebuild that follows service.deleteSubTask().
    //  - Has narrower gesture territory than Dismissible, so the trailing
    //    IconButton's tap recogniser actually wins the gesture arena
    //    instead of being swallowed by a horizontal-pan recogniser
    //    watching the whole tile.
    final readOnly = widget.readOnly;

    final tile = Opacity(
      opacity: _isBreakingDown ? 0.6 : 1.0,
      child: ListTile(
        // Leading: step number, replacing the old per-subtask focus star.
        // The focus toggle moved into the actions sheet (opened by tapping
        // the title) so the tile leading slot can carry positional context
        // instead — "you're on step 4 of 8".
        leading: _SubtaskNumberBadge(
          number: stepNumber,
          isCurrent: isCurrent,
          isCompleted: isCompleted,
        ),
        // Tap the title to open the unified actions sheet (edit, break down,
        // focus, snooze, delete, …). Replaces the old behaviour where tap
        // opened an edit-only sheet and a three-dot button opened the full
        // actions menu — now there's one entry point with no extra trailing
        // affordance to clutter the row.
        title: GestureDetector(
          onTap: (!_isBreakingDown && !readOnly)
              ? () => _showActionsSheet(context, service, isCurrent)
              : null,
          child: Text(
            subtask.description,
            style: isCompleted
                ? TextStyle(
                    decoration: TextDecoration.lineThrough,
                    color: context.palette.muted,
                  )
                : isCurrent
                    ? TextStyle(
                        fontWeight: FontWeight.bold,
                        color: context.palette.strong,
                      )
                    : null,
          ),
        ),
        subtitle: _isBreakingDown
            ? const Text('Breaking down…')
            : _buildSubtitle(context, isCompleted),
        trailing: readOnly
            ? null
            : _buildTrailingAction(
                context,
                service,
                isCurrent,
                isCompleted,
              ),
      ),
    );

    if (readOnly) {
      // No swipe-to-delete on completed goals — the work is done, the plan
      // is frozen for posterity.
      return Material(
        color: Theme.of(context).colorScheme.surface,
        child: tile,
      );
    }

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
              backgroundColor: context.palette.destructive,
              foregroundColor: context.palette.onDestructive,
              icon: AppIcons.delete,
              label: 'Delete',
            ),
          ],
        ),
        child: tile,
      ),
    );
  }

  /// Subtitle for the subtask tile. Communicates state in plain text rather
  /// than relying on icons alone:
  ///   • completed             → "Completed"
  ///   • snoozed               → "Snoozed · wakes [time]"
  ///   • has auto-sleep queued → "Sleeps [duration] when active"
  ///   • otherwise             → null (no subtitle)
  Widget? _buildSubtitle(BuildContext context, bool isCompleted) {
    if (isCompleted) return const Text('Completed');

    if (subtask.state == SubTaskState.snoozed && subtask.snoozedUntil != null) {
      return Text(
        'Snoozed · wakes ${_humaniseWake(subtask.snoozedUntil!)}',
        style: TextStyle(color: context.palette.muted, fontSize: 12),
      );
    }

    final auto = subtask.autoSleepDuration;
    if (auto != null && auto.inSeconds > 0) {
      return Text(
        'Auto-sleeps ${_humaniseDuration(auto)} when active',
        style: TextStyle(color: context.palette.muted, fontSize: 12),
      );
    }
    return null;
  }

  static String _humaniseDuration(Duration d) {
    if (d.inDays >= 1 && d.inHours % 24 == 0) {
      final n = d.inDays;
      return '$n day${n == 1 ? '' : 's'}';
    }
    if (d.inHours >= 1 && d.inMinutes % 60 == 0) {
      final n = d.inHours;
      return '$n hour${n == 1 ? '' : 's'}';
    }
    return '${d.inMinutes} min';
  }

  static String _humaniseWake(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dt.year, dt.month, dt.day);
    final diffDays = target.difference(today).inDays;
    final hhmm =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (diffDays == 0) return 'today $hhmm';
    if (diffDays == 1) return 'tomorrow $hhmm';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.day} $hhmm';
  }

  Widget? _buildTrailingAction(
    BuildContext context,
    GoalService service,
    bool isCurrent,
    bool isCompleted,
  ) {
    // While breaking down, show a spinner — nothing else can be tapped.
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

    // The three-dot menu used to live here; it's now the tile-title tap.
    // The only trailing affordance left is the complete circle on the
    // current step (in active mode).
    if (!isCompleted && isCurrent && widget.showCompletion) {
      return IconButton(
        icon: Icon(AppIcons.complete, color: context.palette.strong),
        tooltip: 'Mark complete',
        onPressed: () => service.completeCurrentSubTask(goal.goalId),
      );
    }
    return null;
  }

  /// Unified action sheet for a subtask — consolidates edit, breakdown,
  /// snooze, auto-sleep, wake, uncomplete, and delete into one place.
  void _showActionsSheet(
    BuildContext context,
    GoalService service,
    bool isCurrent,
  ) {
    final isCompleted = subtask.isCompleted;
    final isSnoozed = subtask.state == SubTaskState.snoozed;
    final isPending = !isCompleted && !isSnoozed;
    final hasAutoSleep = subtask.autoSleepDuration != null;
    final focus = context.read<FocusListService>();
    final inFocus = !isCompleted &&
        focus.isInFocus(goal.goalId, subtask.subtaskId);

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetCtx) => AppBottomSheet(
        title: subtask.description,
        children: [
          // Edit
          if (isPending)
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _showEditSheet(context, service);
              },
            ),

          // Focus toggle — moved here from the old leading star. Doesn't show
          // for completed subtasks (focusing a done step is meaningless).
          if (!isCompleted)
            ListTile(
              leading: Icon(
                inFocus ? Icons.star_rounded : Icons.star_outline_rounded,
                color: inFocus ? context.palette.accent : null,
              ),
              title: Text(
                inFocus
                    ? "Remove from today's focus"
                    : "Add to today's focus",
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                final f = context.read<FocusListService>();
                final repo = context.read<GoalRepository>();
                if (inFocus) {
                  f.unfocusSubtask(goal.goalId, subtask.subtaskId, repo);
                } else {
                  f.focusSubtask(goal.goalId, subtask.subtaskId, repo);
                }
              },
            ),

          // Break down
          if (isPending || isSnoozed)
            ListTile(
              leading: const Icon(AppIcons.breakdown),
              title: const Text('Break down'),
              subtitle: const Text('Split into smaller steps'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _showBreakdownChoiceSheet(context, service);
              },
            ),

          // Snooze — only for the current step in active mode
          if (isPending && isCurrent && widget.showCompletion)
            ListTile(
              leading: const Icon(Icons.bedtime_outlined),
              title: const Text('Snooze'),
              subtitle: const Text('Pause until a specific time'),
              onTap: () async {
                Navigator.pop(sheetCtx);
                final result = await SnoozePickerSheet.show(
                  // ignore: use_build_context_synchronously
                  context,
                  initialUntil: subtask.snoozedUntil,
                  initialNotify: subtask.notifyOnWake,
                );
                if (result != null && mounted) {
                  service.snoozeCurrentSubTask(
                    goal.goalId,
                    until: result.until,
                    notify: result.notify,
                  );
                }
              },
            ),

          // Auto-sleep — for any pending subtask
          if (isPending)
            ListTile(
              leading: Icon(
                Icons.alarm_outlined,
                color: hasAutoSleep ? context.palette.accent : null,
              ),
              title: Text(hasAutoSleep ? 'Edit auto-sleep' : 'Schedule auto-sleep'),
              subtitle: const Text(
                  'Snooze automatically when this step becomes active'),
              onTap: () async {
                Navigator.pop(sheetCtx);
                final result = await AutoSleepPickerSheet.show(
                  // ignore: use_build_context_synchronously
                  context,
                  initial: subtask.autoSleepDuration,
                );
                if (result == null || !mounted) return;
                if (result.cleared) {
                  service.setSubTaskAutoSleep(
                      goal.goalId, subtask.subtaskId, null);
                } else if (result.duration != null) {
                  service.setSubTaskAutoSleep(
                      goal.goalId, subtask.subtaskId, result.duration);
                }
              },
            ),

          // Wake now — only for snoozed subtasks
          if (isSnoozed)
            ListTile(
              leading:
                  Icon(Icons.alarm_on, color: context.palette.accent),
              title: const Text('Wake now'),
              subtitle: const Text('Cancel snooze and resume immediately'),
              onTap: () {
                Navigator.pop(sheetCtx);
                service.wakeSubTask(goal.goalId, subtask.subtaskId);
              },
            ),

          // Mark incomplete — only for completed subtasks in active mode
          if (isCompleted && widget.showCompletion)
            ListTile(
              leading: Icon(AppIcons.uncomplete, color: context.palette.muted),
              title: const Text('Mark incomplete'),
              onTap: () {
                Navigator.pop(sheetCtx);
                service.uncompleteSubTask(goal.goalId, subtask.subtaskId);
              },
            ),

          // Delete — any non-completed subtask
          if (!isCompleted)
            ListTile(
              leading:
                  Icon(AppIcons.delete, color: context.palette.destructive),
              title: Text(
                'Delete',
                style: TextStyle(color: context.palette.destructive),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                service.deleteSubTask(goal.goalId, subtask.subtaskId);
              },
            ),
        ],
      ),
    );
  }

  // Breakdown-specific choice sheet: auto / with-instructions / manual.
  void _showBreakdownChoiceSheet(BuildContext context, GoalService service) {
    final decomp = context.read<GoalDecompositionService>();
    if (!decomp.canAutoBreakdown) {
      _showManualSplitSheet(context, service);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetCtx) => AppBottomSheet(
        title: 'Break down subtask',
        children: [
          ListTile(
            leading: const Icon(AppIcons.aiGenerate),
            title: const Text('Auto-break down'),
            subtitle: const Text('AI generates smaller steps immediately'),
            onTap: () {
              Navigator.pop(sheetCtx);
              _handleSplit(context, service);
            },
          ),
          ListTile(
            leading: const Icon(Icons.tune_outlined),
            title: const Text('Break down with instructions'),
            subtitle: const Text('Guide the AI before it runs'),
            onTap: () {
              Navigator.pop(sheetCtx);
              _showSplitWithInstructions(context, service);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Split manually'),
            subtitle: const Text('Add the smaller steps yourself'),
            onTap: () {
              Navigator.pop(sheetCtx);
              _showManualSplitSheet(context, service);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showSplitWithInstructions(
    BuildContext context,
    GoalService service,
  ) async {
    final decomp = context.read<GoalDecompositionService>();
    if (!decomp.canAutoBreakdown) {
      _showManualSplitSheet(context, service);
      return;
    }
    final draft = context.read<DraftService>();
    final subtaskId = subtask.subtaskId;
    final result =
        await showModalBottomSheet<
          ({String instructions, GoalDifficulty difficulty})
        >(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => _InstructionsSheet(
            hint: 'e.g. keep each step under 5 minutes',
            confirmLabel: 'Break down',
            initialText: draft.breakdownInstructions(subtaskId),
            onDraft: (text) => draft.saveBreakdownInstructions(subtaskId, text),
          ),
        );
    if (result != null && mounted) {
      draft.clearBreakdownInstructions(subtaskId);
      // ignore: use_build_context_synchronously
      _handleSplit(
        this.context,
        service,
        additionalInstructions: result.instructions.isEmpty
            ? null
            : result.instructions,
        difficulty: result.difficulty,
      );
    }
  }

  Future<void> _handleSplit(
    BuildContext context,
    GoalService service, {
    String? additionalInstructions,
    GoalDifficulty? difficulty,
  }) async {
    final decomp = context.read<GoalDecompositionService>();

    if (!decomp.canAutoBreakdown) {
      _showManualSplitSheet(context, service);
      return;
    }

    // Capture messenger and debug flag before the await so we don't reach
    // through context after the widget is potentially disposed.
    final messenger = ScaffoldMessenger.of(context);
    final debugMode = context.read<LlmSettingsService>().debugMode;
    setState(() => _isBreakingDown = true);

    final completedSteps = goal.subtasks
        .where((s) => s.isCompleted)
        .map((s) => s.description)
        .toList();
    final otherPendingSteps = goal.subtasks
        .where((s) => !s.isCompleted && s.subtaskId != subtask.subtaskId)
        .map((s) => s.description)
        .toList();

    Object? llmError;
    final descriptions = await decomp.breakdownSubtask(
      subtask.description,
      additionalInstructions: additionalInstructions,
      difficulty: difficulty ?? goal.difficulty,
      goalTitle: goal.title,
      goalDescription: goal.notes.isNotEmpty ? goal.notes : null,
      completedSteps: completedSteps.isNotEmpty ? completedSteps : null,
      otherPendingSteps:
          otherPendingSteps.isNotEmpty ? otherPendingSteps : null,
      onError: (e) => llmError = e,
    );

    // If the widget was disposed mid-await (e.g. the goal got deleted),
    // bail out before touching state or the service.
    if (!mounted) return;

    if (descriptions == null) {
      setState(() => _isBreakingDown = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(debugMode && llmError != null
              ? llmError.toString()
              : "Couldn't break this down automatically"),
          action: debugMode && llmError != null
              ? null
              : SnackBarAction(
                  label: 'Edit manually',
                  onPressed: () {
                    if (mounted) _showManualSplitSheet(this.context, service);
                  },
                ),
        ),
      );
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

    widget.goalService.splitSubTask(widget.goalId, widget.subtask.subtaskId, [
      step1,
      step2,
    ]);

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
          Icon(Icons.edit_note_outlined,
              size: 48, color: context.palette.muted),
          const SizedBox(height: 12),
          Text('Plan this goal', style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 4),
          Text(
            decomp.canAutoBreakdown
                ? 'Generate subtasks in the card above or add them manually with the + button.'
                : 'Add subtasks using the + button.',
            style: TextStyle(color: context.palette.muted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _InstructionsSheet extends StatefulWidget {
  final String hint;
  final String confirmLabel;
  final String initialText;
  final ValueChanged<String>? onDraft;

  const _InstructionsSheet({
    required this.hint,
    required this.confirmLabel,
    this.initialText = '',
    this.onDraft,
  });

  @override
  State<_InstructionsSheet> createState() => _InstructionsSheetState();
}

class _InstructionsSheetState extends State<_InstructionsSheet> {
  late final TextEditingController _controller;
  GoalDifficulty _difficulty = GoalDifficulty.easy;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    // Always persist what the user typed — caller clears after confirmed.
    widget.onDraft?.call(_controller.text);
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
        const SizedBox(height: 16),
        Text(
          'Breakdown granularity',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 8),
        SegmentedButton<GoalDifficulty>(
          segments: const [
            ButtonSegment(value: GoalDifficulty.easy, label: Text('Few steps')),
            ButtonSegment(
              value: GoalDifficulty.hard,
              label: Text('More steps'),
            ),
            ButtonSegment(
              value: GoalDifficulty.impossible,
              label: Text('Many steps'),
            ),
          ],
          selected: {_difficulty},
          onSelectionChanged: (s) => setState(() => _difficulty = s.first),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => Navigator.pop(context, (
            instructions: _controller.text.trim(),
            difficulty: _difficulty,
          )),
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
            style: TextStyle(color: context.palette.muted),
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
          Icon(AppIcons.addSubtask, size: 48, color: context.palette.muted),
          const SizedBox(height: 12),
          Text('No subtasks yet', style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 4),
          Text(
            'Tap the button below to add your first step',
            style: TextStyle(color: context.palette.muted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Leading position indicator on each SubTaskTile. Shows the step number
/// (1-based index in goal.subtasks) instead of the old focus-toggle star.
///
/// Styling tracks the row state so the badge reads at a glance:
///   • current  → accent-coloured filled circle, white number, bold
///   • completed → muted outlined circle, strikethrough number
///   • pending  → outlined circle, neutral number
///
/// The focus toggle this badge replaces moved into the actions sheet
/// (opened by tapping the tile title).
class _SubtaskNumberBadge extends StatelessWidget {
  final int number;
  final bool isCurrent;
  final bool isCompleted;

  const _SubtaskNumberBadge({
    required this.number,
    required this.isCurrent,
    required this.isCompleted,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color background;
    final Color foreground;
    final Color border;

    if (isCurrent) {
      background = context.palette.accent;
      foreground = cs.onPrimary;
      border = context.palette.accent;
    } else if (isCompleted) {
      background = Colors.transparent;
      foreground = context.palette.muted;
      border = cs.outlineVariant;
    } else {
      background = Colors.transparent;
      foreground = context.palette.muted;
      border = cs.outlineVariant;
    }

    return SizedBox(
      width: 32,
      height: 32,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          shape: BoxShape.circle,
          border: Border.all(color: border, width: 1.5),
        ),
        child: Text(
          '$number',
          style: TextStyle(
            fontSize: 12,
            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
            color: foreground,
            decoration:
                isCompleted ? TextDecoration.lineThrough : TextDecoration.none,
            decorationColor: foreground,
          ),
        ),
      ),
    );
  }
}

// --- AppBar title (emoji + truncated text) ---

class _AppBarTitle extends StatelessWidget {
  final Goal goal;
  const _AppBarTitle({required this.goal});

  @override
  Widget build(BuildContext context) {
    if (goal.emoji == null) {
      return Text(goal.title, overflow: TextOverflow.ellipsis);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GoalSymbol(name: goal.emoji, size: 20),
        const SizedBox(width: 8),
        Flexible(
          child: Text(goal.title, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

// --- Bottom bar variants ---

/// "Queue Goal" bar shown for inbox goals. Commits the plan and pops back.
/// Disabled until at least one subtask has been added so an empty goal can't
/// be queued by accident.
class _QueueGoalBar extends StatelessWidget {
  final Goal goal;
  const _QueueGoalBar({required this.goal});

  @override
  Widget build(BuildContext context) {
    final canQueue = goal.subtasks.isNotEmpty;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: const Icon(Icons.playlist_add_check),
            label: const Text('Queue Goal'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: canQueue
                ? () {
                    context.read<GoalService>().queueGoal(goal.goalId);
                    Navigator.pop(context);
                  }
                : null,
          ),
        ),
      ),
    );
  }
}

/// Sticky bottom bar shown for active goals. Toggles the whole goal in/out
/// of today's focus. When active, every currently-pending subtask is added
/// AND the goal is marked "fully focused" so future subtasks auto-join.
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
                    .focusGoalFully(
                      goal.goalId,
                      context.read<GoalRepository>(),
                    ),
              ),
      ),
    );
  }
}
