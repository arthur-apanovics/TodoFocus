import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/enums.dart';
import '../models/goal.dart';
import '../models/sub_task.dart';
import '../services/decomposition_state.dart';
import '../services/display_preferences.dart';
import '../services/draft_service.dart';
import '../services/focus_list_service.dart' show FocusListService;
import '../services/goal_decomposition_service.dart';
import '../services/goal_repository.dart';
import '../services/goal_service.dart';
import '../services/llm/decomposed_step.dart';
import '../services/settings/llm_settings_service.dart';
import '../theme/app_icons.dart';
import '../theme/app_palette.dart';
import 'widgets/app_bottom_sheet.dart';
import 'widgets/auto_sleep_picker_sheet.dart';
import 'widgets/emoji_picker_sheet.dart';
import 'widgets/estimate_picker_sheet.dart';
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

enum _GoalAction {
  archive,
  delete,
  sendToPlanning,
  clearSubtasks,
  // Single entry point for everything related to time estimates: opens a
  // sub-sheet with both the show/hide toggle and Re-estimate-with-AI. The
  // top-level menu used to surface each as its own item, which crowded the
  // archive/delete actions; folding them under one "Time estimates" header
  // both shortens the menu and groups related controls.
  timeEstimatesSubmenu,
}

/// Resolves whether the time-estimate UI should be visible for [goal]:
///   • per-goal override wins when set (true/false)
///   • otherwise falls back to the global [DisplayPreferences.showTimeEstimates]
bool showEstimatesForGoal(Goal goal, DisplayPreferences prefs) =>
    goal.showTimeEstimatesOverride ?? prefs.showTimeEstimates;

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
    final displayPrefs = context.watch<DisplayPreferences>();
    final estimatesVisible = showEstimatesForGoal(goal, displayPrefs);

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
                _timeEstimatesSubmenuItem(),
                if (goal.subtasks.isNotEmpty)
                  const PopupMenuItem(
                    value: _GoalAction.clearSubtasks,
                    child: ListTile(
                      leading: Icon(Icons.clear_all),
                      title: Text('Clear subtasks'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
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
              itemBuilder: (_) => [
                _timeEstimatesSubmenuItem(),
                const PopupMenuItem(
                  value: _GoalAction.archive,
                  child: ListTile(
                    leading: Icon(Icons.archive_outlined),
                    title: Text('Archive'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                if (goal.subtasks.isNotEmpty)
                  const PopupMenuItem(
                    value: _GoalAction.clearSubtasks,
                    child: ListTile(
                      leading: Icon(Icons.clear_all),
                      title: Text('Clear subtasks'),
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
              showEstimates: estimatesVisible,
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
            const SliverToBoxAdapter(child: _InboxReadyState())
          else if (goal.subtasks.isEmpty)
            const SliverToBoxAdapter(child: _EmptySubtaskState())
          else
            SliverReorderableList(
              itemCount: goal.subtasks.length,
              onReorder: (oldIndex, newIndex) {
                final service = context.read<GoalService>();
                service.reorderSubTask(widget.goalId, oldIndex, newIndex);
              },
              // Subtle elevation + scale lift while a row is being dragged
              // — same affordance the Focus screen uses for goal cards, so
              // the gesture feels consistent across surfaces.
              proxyDecorator: _draggedSubtaskDecorator,
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
                    showEstimate: estimatesVisible,
                  ),
                );
              },
            ),
          // Inline "Add step" affordance rendered AT THE BOTTOM of the
          // subtask list, in-flow — so it visually reads as "this is the
          // tail of the list, tap here to grow it". Replaces the previous
          // floating-action button, which had to be cleared with explicit
          // bottom padding and intercepted taps on the last subtask's
          // action buttons. Shown for any editable, non-generating goal —
          // including empty ones, since the empty / inbox-ready states
          // above are pure guidance text and need a real CTA underneath.
          if (isEditable && !isGenerating)
            SliverToBoxAdapter(
              child: _AddSubtaskInlineButton(
                llmEnabled: llmEnabled,
                onAddManual: () => _showAddSubTaskSheet(context),
                onAddWithAI: () => _showAddWithAISheet(context),
              ),
            ),
          // Tail padding: a touch larger than just the safe-area inset so
          // the focus FAB (when shown for active goals) doesn't cover the
          // inline Add-step button or the last subtask's controls.
          SliverToBoxAdapter(
            child: SizedBox(
              height: isActive ? 128 : 24,
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(context, goal),
      // The Focus toggle lives here for active goals — the FAB slot is
      // free now that Add-subtask moved into the scrolling list. Centred
      // so it doesn't collide with the right-aligned "AI" pill on the
      // inline Add-step tile, and so the three-state colour ladder reads
      // as the screen's primary action rather than a corner accent.
      floatingActionButton: isActive ? _GoalFocusFab(goal: goal) : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  /// Wraps a subtask row mid-drag with a Material lift: rising elevation,
  /// a tiny scale-up, and a rounded shadow. The animation parameter is
  /// driven by `SliverReorderableList` as the row picks up / settles back,
  /// so the lift fades in and out instead of snapping.
  Widget _draggedSubtaskDecorator(
    Widget child,
    int index,
    Animation<double> animation,
  ) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, _) {
        final t = Curves.easeInOut.transform(animation.value);
        final elevation = 12.0 * t;
        final scale = 1.0 + 0.02 * t;
        return Transform.scale(
          scale: scale,
          child: Material(
            elevation: elevation,
            color: Theme.of(context).colorScheme.surface,
            shadowColor: Colors.black.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(10),
            child: child,
          ),
        );
      },
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
      case _GoalAction.clearSubtasks:
        _clearSubtasks(context, goal, service);
      case _GoalAction.timeEstimatesSubmenu:
        _showTimeEstimatesSheet(context, goal, service);
    }
  }

  /// Entry point in the goal's three-dot menu that opens a focused sub-sheet
  /// for time-estimate operations (visibility toggle + AI re-estimate). The
  /// label is static — the dynamic "Show" / "Hide" wording was moved into
  /// the sub-sheet so the top-level menu reads as a stable category, not a
  /// stateful verb.
  PopupMenuItem<_GoalAction> _timeEstimatesSubmenuItem() {
    return const PopupMenuItem(
      value: _GoalAction.timeEstimatesSubmenu,
      child: ListTile(
        leading: Icon(Icons.timer_outlined),
        title: Text('Time estimates'),
        trailing: Icon(Icons.chevron_right, size: 20),
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  void _showTimeEstimatesSheet(
    BuildContext context,
    Goal goal,
    GoalService service,
  ) {
    final prefs = context.read<DisplayPreferences>();
    final visible = showEstimatesForGoal(goal, prefs);
    final llmEnabled = context.read<GoalDecompositionService>().canAutoBreakdown;
    final hasSubtasks = goal.subtasks.isNotEmpty;

    _showTopSheet<void>(
      context: context,
      builder: (sheetCtx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle on the BOTTOM edge of the sheet — it's the side
          // the user would swipe to dismiss, so the affordance hints at
          // "pull me down" rather than "pull me up" (which would be wrong
          // for a top sheet).
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Time estimates',
                    style: Theme.of(sheetCtx).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: Icon(visible
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined),
            title:
                Text(visible ? 'Hide time estimates' : 'Show time estimates'),
            subtitle: Text(
              goal.showTimeEstimatesOverride == null
                  ? 'Follows the global setting'
                  : 'Overrides the global setting for this goal',
              style: TextStyle(color: context.palette.muted, fontSize: 12),
            ),
            onTap: () {
              Navigator.pop(sheetCtx);
              _toggleTimeEstimates(context, goal, service);
            },
          ),
          if (llmEnabled && hasSubtasks)
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('Re-estimate with AI'),
              subtitle: Text(
                'Generates fresh estimates for every step',
                style: TextStyle(color: context.palette.muted, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                _reestimateWithAI(context, goal, service);
              },
            ),
          // Centered drag handle on the bottom edge — mirrors a bottom
          // sheet's top handle but rotated to suggest "swipe upward to
          // dismiss" for this top sheet.
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
            child: Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: context.palette.sheetHandle,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Shows a sheet that slides in from the top of the screen rather than the
  /// bottom. Used for menu items anchored at the top of the AppBar so the
  /// motion matches the trigger's location — opening a sheet from the
  /// bottom when the user just tapped the top corner forces their eye
  /// across the entire screen.
  Future<T?> _showTopSheet<T>({
    required BuildContext context,
    required WidgetBuilder builder,
  }) {
    final cs = Theme.of(context).colorScheme;
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, _, _) {
        return Align(
          alignment: Alignment.topCenter,
          child: SafeArea(
            // Mirror Scaffold's bottom-sheet shape but flipped: rounded
            // corners only on the bottom edge so the sheet reads as
            // "hanging down from the top of the screen".
            child: Material(
              color: cs.surface,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
              ),
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 0),
                child: builder(ctx),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -1),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  void _toggleTimeEstimates(
    BuildContext context,
    Goal goal,
    GoalService service,
  ) {
    final prefs = context.read<DisplayPreferences>();
    final currentlyVisible = showEstimatesForGoal(goal, prefs);
    // Flip to the opposite state. If the flip would just match the global
    // default, clear the override instead so the goal goes back to "follow
    // global" (cleaner state, no stale override left over after the user
    // toggles the global setting later).
    final desired = !currentlyVisible;
    final override = desired == prefs.showTimeEstimates ? null : desired;
    service.setShowTimeEstimatesOverride(goal.goalId, override);
  }

  Future<void> _reestimateWithAI(
    BuildContext context,
    Goal goal,
    GoalService service,
  ) async {
    final decomp = context.read<GoalDecompositionService>();
    final decompState = context.read<DecompositionState>();
    final messenger = ScaffoldMessenger.of(context);
    final debugMode = context.read<LlmSettingsService>().debugMode;

    if (!decomp.canAutoBreakdown) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Configure an AI provider in Settings first.'),
      ));
      return;
    }
    if (goal.subtasks.isEmpty) return;

    final descriptions = goal.subtasks.map((s) => s.description).toList();

    Object? llmError;
    decompState.begin(goal.goalId);
    try {
      final estimates = await decomp.estimateMinutes(
        descriptions,
        goalTitle: goal.title,
        goalDescription: goal.notes.isEmpty ? null : goal.notes,
        onError: (e) => llmError = e,
      );
      if (!mounted) return;
      if (estimates == null) {
        messenger.showSnackBar(SnackBar(
          content: Text(debugMode && llmError != null
              ? llmError.toString()
              : "Couldn't generate estimates"),
        ));
        return;
      }
      final map = <String, int?>{};
      for (var i = 0; i < goal.subtasks.length && i < estimates.length; i++) {
        map[goal.subtasks[i].subtaskId] = estimates[i];
      }
      service.bulkSetSubTaskEstimates(goal.goalId, map);
      // If estimates were hidden because of a per-goal "hide" override, clear
      // it so the user can actually see what the AI produced. (We don't touch
      // the global setting — that stays the user's call.)
      if (goal.showTimeEstimatesOverride == false) {
        service.setShowTimeEstimatesOverride(goal.goalId, null);
      }
    } finally {
      if (mounted) decompState.end(goal.goalId);
    }
  }

  Future<void> _clearSubtasks(
    BuildContext context,
    Goal goal,
    GoalService service,
  ) async {
    if (goal.status == GoalStatus.active) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Clear all subtasks?'),
          content: const Text(
            'All subtasks will be permanently removed. '
            'Your progress on this goal will be lost.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Clear'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
    }
    service.clearSubtasks(goal.goalId);
  }

  /// Bottom bar varies by goal status:
  ///   • inbox     → "Queue Goal" (commits the plan, moves to active)
  ///   • active    → no bar (focus toggle lives in the chip row next to
  ///                 due date / recurrence — see [_GoalFocusChip])
  ///   • completed → no bar (goal is done, no actions)
  Widget? _buildBottomBar(BuildContext context, Goal goal) {
    switch (goal.status) {
      case GoalStatus.inbox:
        return _QueueGoalBar(goal: goal);
      case GoalStatus.active:
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

// ---------------------------------------------------------------------------
// Inline "Add subtask" button rendered at the bottom of the goal's
// subtask list — replaces the previous floating SpeedDial / FAB.
//
// Visual goal: read as a natural extension of the list. The outlined
// tile + the "+" leading icon + the "Add step" label communicate
// "this is the next row, tap here to grow the list". Sitting in-flow
// (not floating) means it doesn't intercept taps on the last real
// subtask, and the user always has a stable, scrollable place to find
// the add affordance.
//
// When an LLM is configured, an "AI" pill on the trailing side opens the
// AI-assisted add flow; the main tile always opens the plain manual
// add sheet. Two explicit affordances feel less mysterious than a single
// button that opens a chooser sheet.
// ---------------------------------------------------------------------------
class _AddSubtaskInlineButton extends StatelessWidget {
  final bool llmEnabled;
  final VoidCallback onAddManual;
  final VoidCallback onAddWithAI;

  const _AddSubtaskInlineButton({
    required this.llmEnabled,
    required this.onAddManual,
    required this.onAddWithAI,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = context.palette.accent;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onAddManual,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            decoration: BoxDecoration(
              border: Border.all(color: cs.outlineVariant, width: 1.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              child: Row(
                children: [
                  Icon(AppIcons.addSubtask, color: accent, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Add step',
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (llmEnabled) _InlineAiPill(onTap: onAddWithAI),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Secondary "AI" affordance on the right of the inline add tile.
/// Tapping it bypasses the main InkWell so the user can pick the AI
/// path without first going through the manual sheet.
class _InlineAiPill extends StatelessWidget {
  final VoidCallback onTap;

  const _InlineAiPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.secondaryContainer,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                AppIcons.aiGenerate,
                size: 14,
                color: cs.onSecondaryContainer,
              ),
              const SizedBox(width: 4),
              Text(
                'AI',
                style: TextStyle(
                  color: cs.onSecondaryContainer,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
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
  // Resolved effective visibility for time estimates on this goal — null
  // when the screen hasn't computed it yet (legacy callers); the header
  // renders the total/remaining line only when this is true and the goal
  // has at least one estimate set.
  final bool showEstimates;

  const _GoalDescriptionCard({
    required this.goal,
    this.onEdit,
    this.showEstimates = false,
  });

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
                  if (showEstimates && goal.hasAnyEstimate) ...[
                    const SizedBox(height: 6),
                    _EstimateSummary(goal: goal),
                  ],
                ],
                const SizedBox(height: 8),
                // Focus toggle lives in the Scaffold's floatingActionButton
                // slot now (see [_GoalFocusFab]) — moved out of this chip
                // row to free space for due date / recurrence and to give
                // the focus action the visual weight it deserves now that
                // the FAB slot isn't claimed by Add-subtask anymore.
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

// --- Time estimate widgets ---

/// Compact trailing chip showing a subtask's time estimate. Renders as
/// `⏱ 30 min`. Tapping it opens the estimate picker. Dimmed when the
/// underlying subtask is completed (so historic estimates still read
/// without competing for attention).
class _EstimateChip extends StatelessWidget {
  final int minutes;
  final bool dimmed;
  final VoidCallback onTap;

  const _EstimateChip({
    required this.minutes,
    required this.onTap,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = dimmed ? context.palette.muted : context.palette.strong;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              formatEstimate(minutes),
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One-line aggregate displayed under the goal progress bar:
///   • when work remains  → "Est. 2h 15m total · 45m left"
///   • when all complete  → "Est. 2h 15m total"
/// Skipped entirely when no subtask has an estimate (Goal.hasAnyEstimate).
class _EstimateSummary extends StatelessWidget {
  final Goal goal;

  const _EstimateSummary({required this.goal});

  @override
  Widget build(BuildContext context) {
    final total = goal.totalEstimatedMinutes;
    final remaining = goal.remainingEstimatedMinutes;
    final hasRemaining = remaining > 0 && remaining != total;

    return Row(
      children: [
        Icon(Icons.schedule, size: 13, color: context.palette.muted),
        const SizedBox(width: 4),
        Text(
          hasRemaining
              ? 'Est. ${formatEstimate(total)} total · '
                  '${formatEstimate(remaining)} left'
              : 'Est. ${formatEstimate(total)} total',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.palette.muted,
              ),
        ),
      ],
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
  // When true, the time estimate (if set) is rendered as a small chip in
  // the trailing area. Resolved by the caller from the global preference +
  // per-goal override.
  final bool showEstimate;

  const SubTaskTile({
    super.key,
    required this.subtask,
    required this.goal,
    this.showCompletion = true,
    this.readOnly = false,
    this.showEstimate = false,
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
          goal: goal,
          subtask: subtask,
          isCurrent: isCurrent,
          isCompleted: isCompleted,
          // Focus toggle is only meaningful for editable, non-completed
          // subtasks on a daily-assignable goal (active). Inbox / completed /
          // archived goals are not focusable at the domain layer
          // (FocusListService guards against it), so we hide the affordance
          // here too rather than letting the user tap a no-op.
          focusToggleEnabled:
              !readOnly && !isCompleted && goal.isDailyAssignable,
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

    // Swipe-to-delete is intentionally gone — delete now lives only in the
    // unified actions sheet (tap the tile title). The previous swipe
    // gesture made the row visually noisy and competed with the reorder
    // long-press for the same horizontal pan territory.
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: tile,
    );
  }

  /// Subtitle for the subtask tile. Renders the estimate chip and any
  /// state label (snoozed/auto-sleep/completed) on a single line below the
  /// title.
  ///
  /// Placing the estimate here — instead of in the trailing slot next to
  /// the complete button — kills a layout shift: when an estimate appeared
  /// or disappeared on the trailing edge, the title text reflowed because
  /// `ListTile.title` shares horizontal space with `trailing`. The subtitle
  /// row is below the title so its width changes don't move anything else.
  Widget? _buildSubtitle(BuildContext context, bool isCompleted) {
    final service = context.read<GoalService>();
    final estimate = subtask.estimatedMinutes;
    final showEstimate =
        widget.showEstimate && estimate != null && !widget.readOnly;

    String? stateText;
    if (isCompleted) {
      stateText = 'Completed';
    } else if (subtask.state == SubTaskState.snoozed &&
        subtask.snoozedUntil != null) {
      stateText = 'Snoozed · wakes ${_humaniseWake(subtask.snoozedUntil!)}';
    } else {
      final auto = subtask.autoSleepDuration;
      if (auto != null && auto.inSeconds > 0) {
        stateText = 'Auto-sleeps ${_humaniseDuration(auto)} when active';
      }
    }

    if (!showEstimate && stateText == null) return null;

    final mutedStyle = TextStyle(color: context.palette.muted, fontSize: 12);
    final separator = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text('·', style: mutedStyle),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showEstimate)
          _EstimateChip(
            minutes: estimate,
            dimmed: isCompleted,
            onTap: () => _showEstimatePicker(context, service),
          ),
        if (showEstimate && stateText != null) separator,
        if (stateText != null)
          Flexible(
            child: Text(
              stateText,
              style: mutedStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
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

    // Trailing slot is now reserved exclusively for the complete-current
    // button — the estimate chip moved underneath the title (see
    // _buildSubtitle) so the row never reflows when an estimate is added
    // or cleared. Without an actionable current step, this slot is empty.
    if (!isCompleted && isCurrent && widget.showCompletion) {
      return IconButton(
        icon: Icon(AppIcons.complete, color: context.palette.strong),
        tooltip: 'Mark complete',
        onPressed: () => service.completeCurrentSubTask(goal.goalId),
      );
    }
    return null;
  }

  Future<void> _showEstimatePicker(
    BuildContext context,
    GoalService service,
  ) async {
    final result = await EstimatePickerSheet.show(
      context,
      initial: subtask.estimatedMinutes,
    );
    if (result == null || !mounted) return;
    service.setSubTaskEstimate(
      goal.goalId,
      subtask.subtaskId,
      result.cleared ? null : result.minutes,
    );
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

          // (Focus toggle used to live here as a list tile, but it moved
          // into the step-number badge in the tile's leading slot — tap the
          // number to add/remove the subtask from today's plan. The badge
          // shows the focus state visually, so no separate sheet entry is
          // needed.)

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

          // (Snooze used to live here for the *current* step in active
          // mode but it doesn't make sense semantically — the active task is
          // what you're working on right now, not something to defer. Pause
          // semantics for upcoming steps are still available via the
          // Auto-sleep entry below, and the Focus tab's group header
          // exposes a snooze action on the goal's front step for the rare
          // "I literally need to step away" case.)

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

          // Time estimate — pending or snoozed subtasks
          if (isPending || isSnoozed)
            ListTile(
              leading: Icon(
                Icons.schedule,
                color: subtask.estimatedMinutes != null
                    ? context.palette.accent
                    : null,
              ),
              title: Text(subtask.estimatedMinutes != null
                  ? 'Edit time estimate'
                  : 'Add time estimate'),
              subtitle: Text(
                subtask.estimatedMinutes != null
                    ? formatEstimate(subtask.estimatedMinutes!)
                    : 'How long will this step take?',
              ),
              onTap: () async {
                Navigator.pop(sheetCtx);
                final result = await EstimatePickerSheet.show(
                  // ignore: use_build_context_synchronously
                  context,
                  initial: subtask.estimatedMinutes,
                );
                if (result == null || !mounted) return;
                service.setSubTaskEstimate(
                  goal.goalId,
                  subtask.subtaskId,
                  result.cleared ? null : result.minutes,
                );
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
      DecomposedStep(step1),
      DecomposedStep(step2),
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
  const _InboxReadyState();

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
                ? 'Generate subtasks in the card above, or use the button below to add them yourself.'
                : 'Use the button below to add your first subtask.',
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
            'Use the button below to add your first step.',
            style: TextStyle(color: context.palette.muted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Leading position indicator on each SubTaskTile. Shows the step number
/// (1-based index in goal.subtasks) and doubles as the per-subtask
/// today's-focus toggle (replacing the old leading star).
///
/// Visual states, in priority order:
///   1. **Completed** → outlined circle, strikethrough number, muted. Not
///      tappable — completed steps are immutable history.
///   2. **Current & focused** → solid accent circle, white bold number,
///      thin outline halo. The "this is what you're doing next *and* it's
///      in today's plan" state. Tap to drop from focus.
///   3. **Current, not focused** → solid accent circle, white bold number,
///      no halo. The natural anchor — tap to add to focus.
///   4. **Focused, not current** → soft accent-tinted circle, accent
///      number. "Queued for today" but not at the front. Tap to drop.
///   5. **Pending, not focused** → outlined circle, neutral number.
///      Tap to add to today's focus.
///
/// When [focusToggleEnabled] is false (e.g. inbox goals or read-only
/// completed goals) the badge still renders state 1/3/5 visually but the
/// tap target is removed — the domain rejects focus on non-active goals
/// and we don't want users hunting a dead button.
class _SubtaskNumberBadge extends StatelessWidget {
  final int number;
  final Goal goal;
  final SubTask subtask;
  final bool isCurrent;
  final bool isCompleted;
  final bool focusToggleEnabled;

  const _SubtaskNumberBadge({
    required this.number,
    required this.goal,
    required this.subtask,
    required this.isCurrent,
    required this.isCompleted,
    required this.focusToggleEnabled,
  });

  @override
  Widget build(BuildContext context) {
    // Watching FocusListService keeps the badge reactive — toggling focus
    // from anywhere else in the app repaints the visual state immediately.
    final focus = context.watch<FocusListService>();
    final inFocus =
        !isCompleted && focus.isInFocus(goal.goalId, subtask.subtaskId);

    final cs = Theme.of(context).colorScheme;
    final palette = context.palette;

    // Resolve a (background, foreground, border) triplet per state.
    final Color background;
    final Color foreground;
    final Color border;
    final double borderWidth;
    final bool bold;

    if (isCompleted) {
      background = Colors.transparent;
      foreground = palette.muted;
      border = cs.outlineVariant;
      borderWidth = 1.5;
      bold = false;
    } else if (isCurrent && inFocus) {
      // Strongest emphasis: current step that's actively focused for today.
      background = palette.accent;
      foreground = cs.onPrimary;
      border = palette.accent;
      borderWidth = 2.5;
      bold = true;
    } else if (isCurrent) {
      // Current but not yet in today's focus.
      background = palette.accent;
      foreground = cs.onPrimary;
      border = palette.accent;
      borderWidth = 1.5;
      bold = true;
    } else if (inFocus) {
      // Queued for today but not the current step.
      background = palette.accent.withValues(alpha: 0.18);
      foreground = palette.accent;
      border = palette.accent;
      borderWidth = 1.5;
      bold = true;
    } else {
      // Plain pending step, not in focus.
      background = Colors.transparent;
      foreground = palette.muted;
      border = cs.outlineVariant;
      borderWidth = 1.5;
      bold = false;
    }

    final badge = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        border: Border.all(color: border, width: borderWidth),
      ),
      child: Text(
        '$number',
        style: TextStyle(
          fontSize: 12,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
          color: foreground,
          decoration:
              isCompleted ? TextDecoration.lineThrough : TextDecoration.none,
          decorationColor: foreground,
        ),
      ),
    );

    if (!focusToggleEnabled || isCompleted) {
      // Decorative only — no interaction. SizedBox preserves the leading slot
      // width so all rows align vertically regardless of tappability.
      return SizedBox(width: 32, height: 32, child: badge);
    }

    return Semantics(
      label: inFocus
          ? "Remove step $number from today's focus"
          : "Add step $number to today's focus",
      button: true,
      child: InkResponse(
        radius: 22,
        onTap: () {
          final f = context.read<FocusListService>();
          final repo = context.read<GoalRepository>();
          if (inFocus) {
            f.unfocusSubtask(goal.goalId, subtask.subtaskId, repo);
          } else {
            f.focusSubtask(goal.goalId, subtask.subtaskId, repo);
          }
        },
        child: badge,
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

/// Floating-action button that toggles whether the whole goal is in today's
/// focus. Promoted from the old chip / sticky bottom bar into the FAB slot
/// now that Add-subtask moved inline into the scrolling list — focus is
/// the most consequential goal-level action, so it earns the persistent
/// bottom-centre anchor.
///
/// Three-state colour ladder so the FAB always reflects the truth of what
/// the user can see on the subtask list (focus stars on each row):
///
///   • [_FocusFabState.none] — no pending subtasks are in today's focus.
///     Tonal `secondaryContainer` background, outlined star. Reads as a
///     quiet, available action.
///   • [_FocusFabState.partial] — at least one but not all pending
///     subtasks are focused. Lighter `primaryContainer` background and a
///     half star, signalling "you're on the way but not committed yet".
///   • [_FocusFabState.full] — every pending subtask is in focus, either
///     via the sticky fully-focused flag OR because the user toggled them
///     all individually. Deepest `primary` background, filled star.
///
/// Tap behaviour collapses to a binary: tapping when full unfocuses the
/// whole goal; tapping when none / partial focuses it fully (which
/// promotes the partial state to full).
class _GoalFocusFab extends StatelessWidget {
  final Goal goal;

  const _GoalFocusFab({required this.goal});

  @override
  Widget build(BuildContext context) {
    final focus = context.watch<FocusListService>();
    final cs = Theme.of(context).colorScheme;
    final state = _resolveState(focus);

    final (background, foreground, icon, tooltip) = switch (state) {
      _FocusFabState.none => (
          cs.secondaryContainer,
          cs.onSecondaryContainer,
          Icons.star_outline_rounded,
          "Add to today's focus",
        ),
      _FocusFabState.partial => (
          cs.primaryContainer,
          cs.onPrimaryContainer,
          Icons.star_half_rounded,
          "Some steps focused — tap to focus the whole goal",
        ),
      _FocusFabState.full => (
          cs.primary,
          cs.onPrimary,
          Icons.star_rounded,
          "Remove from today's focus",
        ),
    };

    return FloatingActionButton.extended(
      heroTag: 'goal_focus_fab_${goal.goalId}',
      tooltip: tooltip,
      backgroundColor: background,
      foregroundColor: foreground,
      icon: Icon(icon),
      label: const Text('Focus'),
      onPressed: () {
        final f = context.read<FocusListService>();
        if (state == _FocusFabState.full) {
          f.unfocusGoalFully(goal.goalId);
        } else {
          // Both none and partial promote to full when tapped — the chip
          // says "Focus the goal", not "Focus one more step".
          f.focusGoalFully(goal.goalId, context.read<GoalRepository>());
        }
      },
    );
  }

  /// Resolves the FAB state by comparing the focused-pending set against
  /// the goal's pending subtasks. `isGoalFullyFocused` is also treated as
  /// full so the sticky-flag path stays consistent with the manual-star
  /// path.
  _FocusFabState _resolveState(FocusListService focus) {
    final pending = goal.subtasks
        .where((s) => s.state == SubTaskState.pending)
        .toList();
    if (pending.isEmpty) {
      // Nothing left to focus. Treat the sticky flag as full so users see
      // their "fully focused" intent preserved even when the goal has run
      // out of pending work; otherwise none.
      return focus.isGoalFullyFocused(goal.goalId)
          ? _FocusFabState.full
          : _FocusFabState.none;
    }
    final focusedPending = focus.focusedPendingIds(goal.goalId, goal).toSet();
    if (focus.isGoalFullyFocused(goal.goalId) ||
        focusedPending.length == pending.length) {
      return _FocusFabState.full;
    }
    if (focusedPending.isEmpty) return _FocusFabState.none;
    return _FocusFabState.partial;
  }
}

enum _FocusFabState { none, partial, full }
