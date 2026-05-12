import 'package:flutter/material.dart';
import '../../services/goal_service.dart';
import '../../services/goal_decomposition_service.dart';
import 'app_bottom_sheet.dart';

class NewGoalSheet extends StatefulWidget {
  final GoalService goalService;
  final GoalDecompositionService decompositionService;

  const NewGoalSheet({
    super.key,
    required this.goalService,
    required this.decompositionService,
  });

  @override
  State<NewGoalSheet> createState() => _NewGoalSheetState();
}

class _NewGoalSheetState extends State<NewGoalSheet> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  DateTime? _dueDate;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _createGoal(BuildContext context) {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    final goal = widget.decompositionService.decompose(
      title: title,
      description: _descriptionController.text.trim(),
      dueDate: _dueDate,
    );

    widget.goalService.addGoal(goal);
    if (context.mounted) Navigator.pop(context);
  }

  void _sendToInbox(BuildContext context) {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    final goal = widget.decompositionService.captureToInbox(
      title: title,
      description: _descriptionController.text.trim(),
    );

    widget.goalService.addGoal(goal);
    if (context.mounted) Navigator.pop(context);
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
          decoration: const InputDecoration(
            labelText: 'Title',
            hintText: 'What do you want to achieve?',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _descriptionController,
          maxLines: 2,
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
