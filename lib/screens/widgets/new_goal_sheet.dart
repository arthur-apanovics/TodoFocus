import 'package:flutter/material.dart';
import '../../services/goal_service.dart';
import '../../services/goal_decomposition_service.dart';

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

  // Tracks whether user wants to decompose now or send to inbox
  bool _sendToInbox = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    final goal = _sendToInbox
        ? widget.decompositionService.captureToInbox(
            title: title,
            description: _descriptionController.text.trim(),
          )
        : widget.decompositionService.decompose(
            title: title,
            description: _descriptionController.text.trim(),
            dueDate: _dueDate,
          );

    widget.goalService.addGoal(goal);

    // context.mounted check — guards against using context after async gap
    // Same concept as checking if a React component is still mounted
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
    return Padding(
      // viewInsets.bottom pushes the sheet up when the keyboard appears
      // Without this the keyboard covers the input fields
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sheet handle — standard Material bottom sheet affordance
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('New Goal', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
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
          // Due date row
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
          // Inbox toggle
          SwitchListTile(
            value: _sendToInbox,
            onChanged: (value) => setState(() => _sendToInbox = value),
            title: const Text('Save to inbox'),
            subtitle: const Text('Decompose into subtasks later'),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _submit,
            child: Text(_sendToInbox ? 'Save to Inbox' : 'Create Goal'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
