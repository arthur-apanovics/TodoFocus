import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/enums.dart';
import '../../models/goal.dart';
import '../../models/sub_task.dart';
import '../../services/daily_reset_service.dart';
import '../../services/display_preferences.dart';
import '../../services/focus_list_service.dart';
import '../../services/goal_queries.dart';
import '../../services/goal_repository.dart';
import '../../theme/app_colors.dart';
import '../goal_planning_screen.dart';
import 'app_bottom_sheet.dart';
import 'goal_symbol.dart';

/// Sheet for adding subtasks to today's focus.
///
/// Each active goal is one [ExpansionTile]. Its leading bulk-star toggles
/// the "fully focused" intent for that goal. Inside, each pending subtask
/// is a checkbox row.
///
/// Selection is **sequential**: ticking subtask N also ticks every pending
/// subtask before it; unticking subtask N unticks every pending subtask
/// after it. The model enforces this in [FocusListService] — the UI just
/// forwards the tap; the cascade happens silently and the checkbox states
/// rebuild from the resulting service state.
///
/// Goals are ordered first by "has pending subtasks" (so empty goals sink
/// to the bottom regardless of sort), then by the user's selected sort
/// order from [DisplayPreferences] — same control as the Goals list, so the
/// two views stay in step. Long-pressing a goal title navigates to that
/// goal so the user can quickly add/edit subtasks before scheduling them —
/// the sheet stays open so the user returns to the picker after navigating
/// back.
class FocusPickerSheet extends StatefulWidget {
  const FocusPickerSheet({super.key});

  @override
  State<FocusPickerSheet> createState() => _FocusPickerSheetState();
}

class _FocusPickerSheetState extends State<FocusPickerSheet> {
  /// Tracks whether each goal's section is currently expanded.
  /// Populated lazily on first build from focus state (goals with focused
  /// subtasks start expanded; the rest start collapsed).
  final Map<String, bool> _expandedByGoalId = {};

  /// Incremented when the user hits the expand-all / collapse-all button so
  /// that a new [ValueKey] is generated for each [_GoalSection], forcing the
  /// widget subtree to recreate with the updated [initiallyExpanded] value.
  int _expandVersion = 0;

  /// Null = use per-goal defaults.
  /// True/false = override applied by the last expand-all/collapse-all action.
  bool? _forcedExpansion;

  void _initExpanded(List<Goal> goals, FocusListService focus) {
    for (final goal in goals) {
      if (_expandedByGoalId.containsKey(goal.goalId)) continue;
      final hasFocused =
          focus.focusedPendingIds(goal.goalId, goal).isNotEmpty;
      _expandedByGoalId[goal.goalId] = hasFocused;
    }
  }

  bool get _anyExpanded => _expandedByGoalId.values.any((v) => v);

  void _toggleAll(List<Goal> goals) {
    final expand = !_anyExpanded;
    setState(() {
      for (final goal in goals) {
        _expandedByGoalId[goal.goalId] = expand;
      }
      _forcedExpansion = expand;
      _expandVersion++;
    });
  }

  void _onSectionExpansionChanged(String goalId, bool expanded) {
    // No setState needed here — we only read _anyExpanded when building the
    // toggle button, which rebuilds on the next user interaction anyway.
    // Keeping this lightweight avoids spurious redraws on every tile tap.
    _expandedByGoalId[goalId] = expanded;
    // Clear forced override so subsequent toggles respect per-goal state.
    _forcedExpansion = null;
  }

  @override
  Widget build(BuildContext context) {
    final queries = context.watch<GoalQueries>();
    final reset = context.watch<DailyResetService>();
    final prefs = context.watch<DisplayPreferences>();
    final focus = context.watch<FocusListService>();

    final sorted = _orderForPicker(queries.goals, reset, prefs.sortOrder);

    // Lazy-init expansion tracking for any goals not yet seen.
    _initExpanded(sorted, focus);

    // Smart sort: display goals grouped by category.
    final useCategories = prefs.sortOrder == GoalSortOrder.smart;
    final categories = useCategories
        ? reset.categorizeForSmart(
            sorted.where((g) => g.subtasks.any((s) => s.state == SubTaskState.pending)).toList() +
            sorted.where((g) => !g.subtasks.any((s) => s.state == SubTaskState.pending)).toList(),
          )
        : null;

    // Flatten the ordered list for expand-all/collapse-all scope.
    final allGoalsForToggle = categories != null
        ? [for (final c in categories) ...c.goals]
        : sorted;

    return AppBottomSheet(
      title: 'Pick subtasks for today',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (sorted.isNotEmpty)
            IconButton(
              icon: Icon(
                _anyExpanded ? Icons.unfold_less : Icons.unfold_more,
              ),
              tooltip: _anyExpanded ? 'Collapse all' : 'Expand all',
              onPressed: () => _toggleAll(allGoalsForToggle),
            ),
          _SortMenuButton(current: prefs.sortOrder),
        ],
      ),
      children: [
        if (sorted.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
            child: Text(
              'No active goals yet — create one first.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted),
            ),
          )
        else
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                if (categories != null)
                  ..._buildCategorized(categories)
                else
                  for (final goal in sorted)
                    _GoalSection(
                      key: ValueKey('${goal.goalId}_$_expandVersion'),
                      goal: goal,
                      initiallyExpanded:
                          _forcedExpansion ?? _expandedByGoalId[goal.goalId] ?? false,
                      onExpansionChanged: (e) =>
                          _onSectionExpansionChanged(goal.goalId, e),
                    ),
              ],
            ),
          ),
      ],
    );
  }

  List<Widget> _buildCategorized(
      List<({String label, List<Goal> goals})> categories) {
    final widgets = <Widget>[];
    for (final category in categories) {
      widgets.add(_PickerCategoryHeader(label: category.label));
      for (final goal in category.goals) {
        widgets.add(_GoalSection(
          key: ValueKey('${goal.goalId}_$_expandVersion'),
          goal: goal,
          initiallyExpanded:
              _forcedExpansion ?? _expandedByGoalId[goal.goalId] ?? false,
          onExpansionChanged: (e) =>
              _onSectionExpansionChanged(goal.goalId, e),
        ));
      }
    }
    return widgets;
  }

  /// Sorts goals for the picker:
  ///   1. Goals with pending subtasks come first (no point scheduling a
  ///      goal you can't add anything from).
  ///   2. Within each bucket, the user's preferred sort order is applied
  ///      via [DailyResetService.sortGoals] — same logic as the Goals tab.
  static List<Goal> _orderForPicker(
    List<Goal> goals,
    DailyResetService reset,
    GoalSortOrder order,
  ) {
    final withPending = <Goal>[];
    final withoutPending = <Goal>[];
    for (final goal in goals) {
      final hasPending =
          goal.subtasks.any((s) => s.state == SubTaskState.pending);
      (hasPending ? withPending : withoutPending).add(goal);
    }
    return [
      ...reset.sortGoals(withPending, order),
      ...reset.sortGoals(withoutPending, order),
    ];
  }
}

/// Slim section label for categorized picker display (Smart sort).
class _PickerCategoryHeader extends StatelessWidget {
  final String label;
  const _PickerCategoryHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 2),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.muted,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// IconButton that opens a popup menu to switch the [DisplayPreferences]
/// sort order. Mirrors the sort button on the Goals tab so the user only
/// has to learn one control.
class _SortMenuButton extends StatelessWidget {
  final GoalSortOrder current;

  const _SortMenuButton({required this.current});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<GoalSortOrder>(
      icon: const Icon(Icons.sort),
      tooltip: 'Sort goals',
      initialValue: current,
      onSelected: (v) =>
          context.read<DisplayPreferences>().setSortOrder(v),
      itemBuilder: (_) => [
        _item(GoalSortOrder.dateAdded, 'Date added', current),
        _item(GoalSortOrder.urgency, 'Urgency', current),
        _item(GoalSortOrder.smart, 'Smart', current),
      ],
    );
  }

  PopupMenuItem<GoalSortOrder> _item(
    GoalSortOrder value,
    String label,
    GoalSortOrder current,
  ) {
    return PopupMenuItem(
      value: value,
      child: ListTile(
        title: Text(label),
        trailing:
            current == value ? const Icon(Icons.check, size: 18) : null,
        contentPadding: EdgeInsets.zero,
        dense: true,
        minLeadingWidth: 0,
      ),
    );
  }
}

class _GoalSection extends StatelessWidget {
  final Goal goal;
  final bool initiallyExpanded;
  final void Function(bool expanded) onExpansionChanged;

  const _GoalSection({
    super.key,
    required this.goal,
    required this.initiallyExpanded,
    required this.onExpansionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final focus = context.watch<FocusListService>();
    final pending = goal.subtasks
        .where((s) => s.state == SubTaskState.pending)
        .toList();

    if (pending.isEmpty) {
      // Greyed out — keeps the goal discoverable (you can still tap the
      // title to navigate) but communicates there's nothing to schedule.
      return ListTile(
        leading: Icon(Icons.check_circle, color: AppColors.muted),
        title: GestureDetector(
          onLongPress: () => _openGoal(context),
          child: Text(goal.title, style: TextStyle(color: AppColors.muted)),
        ),
        subtitle: const Text('No pending subtasks'),
        dense: true,
      );
    }

    final focusedPending =
        focus.focusedPendingIds(goal.goalId, goal).toSet();
    final allFocused = focus.isGoalFullyFocused(goal.goalId) ||
        focusedPending.length == pending.length;
    final noneFocused = focusedPending.isEmpty;
    final mixed = !allFocused && !noneFocused;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        onExpansionChanged: onExpansionChanged,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: _BulkStarButton(
          allFocused: allFocused,
          mixed: mixed,
          onTap: () {
            final f = context.read<FocusListService>();
            final repo = context.read<GoalRepository>();
            if (allFocused) {
              f.unfocusGoalFully(goal.goalId);
            } else {
              f.focusGoalFully(goal.goalId, repo);
            }
          },
        ),
        // Long-press anywhere on the header to jump into the goal screen.
        // The sheet stays open underneath so the user returns to the picker
        // after navigating back — no state is lost.
        // Tap still expands/collapses (default ExpansionTile behaviour) —
        // gesture arena handles the disambiguation since long-press and tap
        // are different recognisers.
        title: GestureDetector(
          onLongPress: () => _openGoal(context),
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              if (goal.emoji != null) ...[
                GoalSymbol(name: goal.emoji, size: 18),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(goal.title, overflow: TextOverflow.ellipsis),
                    if (goal.dueDate != null)
                      _PickerDueDateLabel(dueDate: goal.dueDate!),
                  ],
                ),
              ),
              Text(
                '${focusedPending.length}/${pending.length}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.muted,
                    ),
              ),
            ],
          ),
        ),
        childrenPadding: const EdgeInsets.only(bottom: 4),
        children: [
          for (var i = 0; i < pending.length; i++)
            _SequentialRow(
              goalId: goal.goalId,
              subtask: pending[i],
              positionLabel: '${i + 1}',
              isInFocus: focusedPending.contains(pending[i].subtaskId),
            ),
        ],
      ),
    );
  }

  void _openGoal(BuildContext context) {
    // Push WITHOUT closing the sheet — the bottom sheet route stays in the
    // navigator stack so the user returns to the picker when they pop back.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GoalPlanningScreen(goalId: goal.goalId),
      ),
    );
  }
}

/// Compact due-date label shown below the goal title in the picker.
class _PickerDueDateLabel extends StatelessWidget {
  final DateTime dueDate;
  const _PickerDueDateLabel({required this.dueDate});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final diff = d.difference(today).inDays;

    final String label;
    final Color color;
    if (diff < 0) {
      label = '${diff.abs()}d overdue';
      color = Theme.of(context).colorScheme.error;
    } else if (diff == 0) {
      label = 'due today';
      color = Theme.of(context).colorScheme.error;
    } else if (diff == 1) {
      label = 'due tomorrow';
      color = AppColors.accent;
    } else if (diff <= 7) {
      label = 'due in ${diff}d';
      color = AppColors.accent;
    } else {
      final months = ['Jan','Feb','Mar','Apr','May','Jun',
                      'Jul','Aug','Sep','Oct','Nov','Dec'];
      label = '${months[dueDate.month - 1]} ${dueDate.day}';
      color = AppColors.muted;
    }

    return Text(
      label,
      style: TextStyle(fontSize: 11, color: color),
    );
  }
}

class _BulkStarButton extends StatelessWidget {
  final bool allFocused;
  final bool mixed;
  final VoidCallback onTap;

  const _BulkStarButton({
    required this.allFocused,
    required this.mixed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color color;
    if (allFocused) {
      icon = Icons.star_rounded;
      color = AppColors.accent;
    } else if (mixed) {
      icon = Icons.star_half_rounded;
      color = AppColors.accent;
    } else {
      icon = Icons.star_outline_rounded;
      color = AppColors.muted;
    }
    return IconButton(
      icon: Icon(icon, color: color, size: 28),
      tooltip: allFocused
          ? 'Remove all from today\'s focus'
          : 'Add all pending to today\'s focus',
      onPressed: onTap,
    );
  }
}

/// A single pending-subtask row in the picker. Number prefix communicates
/// the sequential position so users notice the "this is step N of M" framing.
class _SequentialRow extends StatelessWidget {
  final String goalId;
  final SubTask subtask;
  final String positionLabel;
  final bool isInFocus;

  const _SequentialRow({
    required this.goalId,
    required this.subtask,
    required this.positionLabel,
    required this.isInFocus,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _toggle(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 16, 4),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                positionLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                ),
              ),
            ),
            Expanded(
              child: Text(
                subtask.description,
                style: const TextStyle(fontSize: 14),
              ),
            ),
            Checkbox(
              value: isInFocus,
              onChanged: (_) => _toggle(context),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  void _toggle(BuildContext context) {
    final f = context.read<FocusListService>();
    final repo = context.read<GoalRepository>();
    if (isInFocus) {
      f.unfocusSubtask(goalId, subtask.subtaskId, repo);
    } else {
      f.focusSubtask(goalId, subtask.subtaskId, repo);
    }
  }
}
