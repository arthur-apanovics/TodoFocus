import 'package:flutter/material.dart';
import '../../models/enums.dart';
import '../../services/draft_service.dart';
import '../../services/goal_decomposition_service.dart';
import '../../services/goal_service.dart';
import 'app_bottom_sheet.dart';

// Quick-capture sheet. Two paths:
//   "Save"  → goal lands in the Planning tab as inbox; sheet closes.
//   "Plan"  → goal lands in the Planning tab AND the sheet returns the
//             goalId so the caller can push GoalPlanningScreen immediately.
//
// Metadata (difficulty, due date, emoji) is set later on the planning
// screen — capturing only title + description keeps the friction low.
class NewGoalSheet extends StatefulWidget {
  final GoalService goalService;
  final GoalDecompositionService decompositionService;
  final DraftService draftService;

  const NewGoalSheet({
    super.key,
    required this.goalService,
    required this.decompositionService,
    required this.draftService,
  });

  @override
  State<NewGoalSheet> createState() => _NewGoalSheetState();
}

class _NewGoalSheetState extends State<NewGoalSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  final _descriptionFocus = FocusNode();

  // Prevents dispose() from saving after a successful submission.
  bool _submitted = false;

  DraftService get _draft => widget.draftService;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: _draft.newGoalTitle);
    _descriptionController =
        TextEditingController(text: _draft.newGoalDescription);
  }

  @override
  void dispose() {
    if (!_submitted) {
      _draft.saveNewGoal(
        title: _titleController.text,
        description: _descriptionController.text,
        dueDate: null,
        difficulty: GoalDifficulty.easy,
      );
    }
    _titleController.dispose();
    _descriptionController.dispose();
    _descriptionFocus.dispose();
    super.dispose();
  }

  // Creates the inbox goal and returns its id. Returns null if validation
  // fails so callers can short-circuit without further work.
  String? _capture() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return null;

    _submitted = true;
    _draft.clearNewGoal();

    final description = _descriptionController.text.trim();
    final goal = widget.decompositionService.captureToInbox(
      title: title,
      description: description.isEmpty ? null : description,
    );
    widget.goalService.addGoal(goal);
    return goal.goalId;
  }

  void _save(BuildContext context) {
    final goalId = _capture();
    if (goalId == null || !context.mounted) return;
    Navigator.pop(context);
  }

  void _plan(BuildContext context) {
    final goalId = _capture();
    if (goalId == null || !context.mounted) return;
    Navigator.pop(context, goalId);
  }

  void _clearFields() {
    _draft.clearNewGoal();
    _titleController.text = '';
    _descriptionController.text = '';
  }

  @override
  Widget build(BuildContext context) {
    return AppBottomSheet(
      title: 'New Goal',
      trailing: IconButton(
        icon: const Icon(Icons.clear_all),
        tooltip: 'Clear all fields',
        onPressed: _clearFields,
      ),
      children: [
        TextField(
          controller: _titleController,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _descriptionFocus.requestFocus(),
          decoration: const InputDecoration(
            labelText: 'Title',
            hintText: 'What do you want to achieve?',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _descriptionController,
          focusNode: _descriptionFocus,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Description (optional)',
            hintText: 'Any extra context...',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        _SplitSubmitButton(
          onPlan: () => _plan(context),
          onSave: () => _save(context),
        ),
      ],
    );
  }
}

// Split button — left half is the primary "Plan" action (opens the planning
// screen), right half is the quick "Save to inbox" icon for users who just
// want to capture without planning right now.
class _SplitSubmitButton extends StatelessWidget {
  final VoidCallback onPlan;
  final VoidCallback onSave;

  const _SplitSubmitButton({required this.onPlan, required this.onSave});

  static const _height = 48.0;
  static const _outerRadius = Radius.circular(12);
  static const _innerRadius = Radius.zero;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: _height,
      child: Row(
        children: [
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
              onPressed: onPlan,
              icon: const Icon(Icons.format_list_numbered_outlined, size: 18),
              label: const Text('Plan'),
            ),
          ),
          Container(
            width: 1,
            color: cs.onPrimary.withValues(alpha: 0.30),
          ),
          Tooltip(
            message: 'Save to inbox',
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
              onPressed: onSave,
              child: const Icon(Icons.inbox_outlined, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
