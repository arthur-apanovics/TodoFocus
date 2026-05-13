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
  bool _loading = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _createGoal(BuildContext context) async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    setState(() => _loading = true);

    bool usedFallback = false;
    final goal = await widget.decompositionService.decompose(
      title: title,
      description: _descriptionController.text.trim(),
      dueDate: _dueDate,
      onLlmFallback: () => usedFallback = true,
    );

    widget.goalService.addGoal(goal);

    if (!context.mounted) return;

    // Capture messenger before popping — the sheet's context is invalid after pop.
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context, goal.goalId);

    if (usedFallback) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('AI assistant unavailable — used smart templates instead'),
          duration: Duration(seconds: 4),
        ),
      );
    }
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
          enabled: !_loading,
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
          enabled: !_loading,
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
              onPressed: _loading ? null : _pickDueDate,
              child: Text(
                _dueDate == null
                    ? 'Set due date (optional)'
                    : 'Due: ${_dueDate!.day}/${_dueDate!.month}/${_dueDate!.year}',
              ),
            ),
            if (_dueDate != null)
              IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed:
                    _loading ? null : () => setState(() => _dueDate = null),
              ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _loading ? null : () => _sendToInbox(context),
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
          onPressed: _loading ? null : () => _createGoal(context),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Row(
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
