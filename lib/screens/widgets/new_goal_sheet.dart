import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import '../../models/enums.dart';
import '../../services/decomposition_state.dart';
import '../../services/draft_service.dart';
import '../../services/goal_service.dart';
import '../../services/goal_decomposition_service.dart';
import 'app_bottom_sheet.dart';
import 'emoji_picker_sheet.dart';
import 'goal_symbol.dart';

class NewGoalSheet extends StatefulWidget {
  final GoalService goalService;
  final GoalDecompositionService decompositionService;
  final DecompositionState decompositionState;
  final DraftService draftService;

  const NewGoalSheet({
    super.key,
    required this.goalService,
    required this.decompositionService,
    required this.decompositionState,
    required this.draftService,
  });

  @override
  State<NewGoalSheet> createState() => _NewGoalSheetState();
}

class _NewGoalSheetState extends State<NewGoalSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  final _descriptionFocus = FocusNode();
  DateTime? _dueDate;
  GoalDifficulty _difficulty = GoalDifficulty.easy;
  String? _emoji;

  // Prevents dispose() from saving after a successful submission.
  bool _submitted = false;

  DraftService get _draft => widget.draftService;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: _draft.newGoalTitle);
    _descriptionController =
        TextEditingController(text: _draft.newGoalDescription);
    _dueDate = _draft.newGoalDueDate;
    _difficulty = _draft.newGoalDifficulty;
  }

  @override
  void dispose() {
    if (!_submitted) {
      _draft.saveNewGoal(
        title: _titleController.text,
        description: _descriptionController.text,
        dueDate: _dueDate,
        difficulty: _difficulty,
      );
    }
    _titleController.dispose();
    _descriptionController.dispose();
    _descriptionFocus.dispose();
    super.dispose();
  }

  void _createGoal(BuildContext context) {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    _submitted = true;
    _draft.clearNewGoal();

    final description = _descriptionController.text.trim();
    final goal = widget.decompositionService.createGoal(
      title: title,
      description: description.isEmpty ? null : description,
      dueDate: _dueDate,
      difficulty: _difficulty,
    );
    widget.goalService.addGoal(goal);
    if (_emoji != null) {
      widget.goalService.setEmoji(goal.goalId, _emoji!);
    }

    // Navigate immediately — subtasks populate asynchronously in the detail screen.
    if (!context.mounted) return;
    Navigator.pop(context, goal.goalId);

    unawaited(widget.decompositionService.decomposeInBackground(
      goalId: goal.goalId,
      title: goal.title,
      description: goal.notes.isEmpty ? null : goal.notes,
      onResult: (descriptions) =>
          widget.goalService.replaceAllSubTasks(goal.goalId, descriptions),
      onEmoji: (emoji) => widget.goalService.setEmoji(goal.goalId, emoji),
      state: widget.decompositionState,
      difficulty: _difficulty,
    ));
  }

  void _sendToInbox(BuildContext context) {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    _submitted = true;
    _draft.clearNewGoal();

    final description = _descriptionController.text.trim();
    final goal = widget.decompositionService.captureToInbox(
      title: title,
      description: description.isEmpty ? null : description,
      difficulty: _difficulty,
    );
    widget.goalService.addGoal(goal);

    if (!context.mounted) return;
    Navigator.pop(context);
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }

  void _clearFields() {
    _draft.clearNewGoal();
    _titleController.text = '';
    _descriptionController.text = '';
    setState(() {
      _dueDate = null;
      _difficulty = GoalDifficulty.easy;
      _emoji = null;
    });
  }

  Future<void> _pickEmoji() async {
    final picked = await showEmojiPickerSheet(context);
    if (picked != null && mounted) setState(() => _emoji = picked);
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
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Description (optional)',
            hintText: 'Any extra context...',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            GestureDetector(
              onTap: _pickEmoji,
              child: Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _emoji != null
                    ? GoalSymbol(name: _emoji, size: 28)
                    : Icon(
                        Icons.add_reaction_outlined,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _emoji != null ? 'Tap to change emoji' : 'Add an emoji (optional)',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (_emoji != null)
              IconButton(
                icon: const Icon(Icons.clear, size: 18),
                tooltip: 'Remove emoji',
                onPressed: () => setState(() { _emoji = null; }),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.calendar_today_outlined, size: 18),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _pickDueDate,
              child: Text(
                _dueDate == null
                    ? 'Set due date (optional)'
                    : 'Due: ${_dueDate!.day}/${_dueDate!.month}/${_dueDate!.year}',
              ),
            ),
            if (_dueDate != null)
              IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () => setState(() => _dueDate = null),
              ),
          ],
        ),
        const SizedBox(height: 4),
        _DifficultySelector(
          value: _difficulty,
          onChanged: (d) => setState(() => _difficulty = d),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => _sendToInbox(context),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.inbox_outlined, size: 18),
              SizedBox(width: 8),
              Text('Save to Inbox'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () => _createGoal(context),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.flag_outlined, size: 18),
              SizedBox(width: 8),
              Text('Create Goal'),
            ],
          ),
        ),
      ],
    );
  }
}

class _DifficultySelector extends StatelessWidget {
  final GoalDifficulty value;
  final ValueChanged<GoalDifficulty> onChanged;

  const _DifficultySelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.tune_outlined, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: SegmentedButton<GoalDifficulty>(
            segments: GoalDifficulty.values
                .map(
                  (d) => ButtonSegment(
                    value: d,
                    label: Text(d.displayName),
                  ),
                )
                .toList(),
            selected: {value},
            onSelectionChanged: (s) => onChanged(s.first),
            showSelectedIcon: false,
          ),
        ),
      ],
    );
  }
}
