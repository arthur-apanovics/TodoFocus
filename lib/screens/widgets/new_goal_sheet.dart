import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import '../../services/decomposition_state.dart';
import '../../services/goal_service.dart';
import '../../services/goal_decomposition_service.dart';
import 'app_bottom_sheet.dart';

class NewGoalSheet extends StatefulWidget {
  final GoalService goalService;
  final GoalDecompositionService decompositionService;
  final DecompositionState decompositionState;

  const NewGoalSheet({
    super.key,
    required this.goalService,
    required this.decompositionService,
    required this.decompositionState,
  });

  @override
  State<NewGoalSheet> createState() => _NewGoalSheetState();
}

class _NewGoalSheetState extends State<NewGoalSheet> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _descriptionFocus = FocusNode();
  DateTime? _dueDate;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _descriptionFocus.dispose();
    super.dispose();
  }

  void _createGoal(BuildContext context) {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    final description = _descriptionController.text.trim();

    final goal = widget.decompositionService.createGoal(
      title: title,
      description: description.isEmpty ? null : description,
      dueDate: _dueDate,
    );
    widget.goalService.addGoal(goal);

    // Navigate immediately — subtasks populate asynchronously in the detail screen.
    if (!context.mounted) return;
    Navigator.pop(context, goal.goalId);

    unawaited(widget.decompositionService.decomposeInBackground(
      goalId: goal.goalId,
      title: goal.title,
      description: goal.notes.isEmpty ? null : goal.notes,
      onResult: (descriptions) =>
          widget.goalService.replaceAllSubTasks(goal.goalId, descriptions),
      state: widget.decompositionState,
    ));
  }

  void _sendToInbox(BuildContext context) {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    final description = _descriptionController.text.trim();

    final goal = widget.decompositionService.captureToInbox(
      title: title,
      description: description.isEmpty ? null : description,
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

  @override
  Widget build(BuildContext context) {
    return AppBottomSheet(
      title: 'New Goal',
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
