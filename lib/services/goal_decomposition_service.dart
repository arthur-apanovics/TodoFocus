import 'package:uuid/uuid.dart'; // we'll add this below
import '../models/enums.dart';
import '../models/goal.dart';
import '../models/sub_task.dart';

class GoalDecompositionService {
  final Uuid _uuid = const Uuid();

  // The single public method — takes raw user input, returns a structured Goal.
  // This is the method signature that stays the same when the LLM replaces the internals.
  Goal decompose({
    required String title,
    String? description,
    DateTime? dueDate,
  }) {
    final goalId = _uuid.v4();

    return Goal(
      goalId: goalId,
      title: title,
      notes: description ?? '',
      dueDate: dueDate,
      subtasks: _scaffoldSubTasks(goalId, title, description),
    );
  }

  // Captures a raw goal into the inbox without decomposing it
  Goal captureToInbox({required String title, String? description}) {
    return Goal(
      goalId: _uuid.v4(),
      title: title,
      notes: description ?? '',
      status: GoalStatus.inbox,
      subtasks: [], // no subtasks yet — decomposition happens later
    );
  }

  // Private — the LLM will replace this method body entirely, nothing else changes
  List<SubTask> _scaffoldSubTasks(
    String goalId,
    String title,
    String? description,
  ) {
    final intent = _detectIntent(title, description);
    final templates = _templatesByIntent[intent] ?? _templatesByIntent['fallback']!;

    // All start as pending — the first one is implicitly
    // current because it's the first non-completed subtask
    return templates
        .map((desc) => SubTask(subtaskId: _uuid.v4(), description: desc))
        .toList();
  }

  // Scans title then description for the first recognised action verb.
  // Returns a key into _templatesByIntent, or 'fallback' if nothing matches.
  String _detectIntent(String title, String? description) {
    final text = '${title.toLowerCase()} ${(description ?? '').toLowerCase()}';

    // Order matters: more specific phrases come first so they win over
    // broader single-word matches further down the list.
    const patterns = <String, List<String>>{
      // Everyday / one-shot tasks
      'reminder': ['remember to', "don't forget", 'do not forget', 'dont forget'],
      'errand': ['pick up', 'pickup', 'drop off', 'dropoff', 'drop by', 'collect from'],
      'travel': ['trip', 'vacation', 'holiday', 'flight', 'hotel', 'fly to', 'drive to', 'travel'],
      'cook': ['cook', 'bake', 'meal prep', 'prepare meal', 'make dinner', 'make lunch', 'make breakfast'],
      'apply': ['apply for', 'submit application'],
      'appointment': ['book', 'reschedule', 'appointment'],
      'buy': ['buy', 'purchase', 'order', 'shop for'],
      'call': ['call', 'phone', 'email', 'text', 'message', 'contact', 'reach out'],
      'clean': ['clean', 'tidy', 'declutter', 'wash', 'do laundry', 'vacuum'],
      'pay': ['pay', 'renew', 'file taxes'],
      // Project / improvement tasks
      'learn': ['learn', 'study', 'understand', 'master', 'practise', 'practice'],
      'build': ['build', 'develop', 'implement', 'code', 'program', 'create'],
      'write': ['write', 'draft', 'author', 'document', 'compose', 'blog', 'essay'],
      'plan': ['plan', 'organise', 'organize', 'prepare', 'schedule', 'arrange', 'set up'],
      'read': ['read', 'finish reading', 'go through'],
      'fix': ['fix', 'debug', 'solve', 'resolve', 'troubleshoot', 'repair'],
      'research': ['research', 'investigate', 'analyse', 'analyze', 'audit', 'evaluate'],
      'launch': ['launch', 'ship', 'release', 'deploy', 'publish'],
      'design': ['design', 'prototype', 'wireframe', 'mockup', 'sketch', 'redesign'],
      'exercise': ['exercise', 'workout', 'work out', 'train', 'jog', 'stretch'],
    };

    for (final entry in patterns.entries) {
      for (final keyword in entry.value) {
        // Match at word boundary to avoid partial matches (e.g. "plan" inside "explain")
        final escaped = RegExp.escape(keyword);
        if (RegExp(r'(^|\s)' + escaped + r'(\s|$)').hasMatch(text)) {
          return entry.key;
        }
      }
    }

    return 'fallback';
  }

  static const _templatesByIntent = <String, List<String>>{
    'reminder': [
      'Note when this needs to happen',
      'Do the task',
    ],
    'errand': [
      'Confirm details (location, hours, what you need)',
      'Plan when you will go',
      'Run the errand',
      'Confirm it is done',
    ],
    'travel': [
      'Decide dates and destination',
      'Book transport',
      'Book accommodation',
      'Plan activities and itinerary',
      'Pack and prepare for departure',
    ],
    'cook': [
      'Choose the recipe',
      'Check pantry and shop for missing ingredients',
      'Prep ingredients',
      'Cook the meal',
      'Serve and clean up',
    ],
    'apply': [
      'Check requirements and deadlines',
      'Gather necessary documents',
      'Fill out the application',
      'Review and submit',
      'Track and follow up',
    ],
    'appointment': [
      'Identify provider or options',
      'Pick a time that works',
      'Book or confirm the appointment',
      'Add it to your calendar',
      'Prepare anything needed beforehand',
    ],
    'buy': [
      'Clarify what you need and your budget',
      'Research and compare options',
      'Decide on the purchase',
      'Place the order',
      'Confirm receipt or delivery',
    ],
    'call': [
      'Note what you want to say or ask',
      'Find the right contact info',
      'Make the call or send the message',
      'Follow up if needed',
    ],
    'clean': [
      'Gather supplies',
      'Clear and declutter the space',
      'Clean surfaces',
      'Put things back in place',
      'Take out trash and finish up',
    ],
    'pay': [
      'Confirm amount and deadline',
      'Make the payment',
      'Save the confirmation or receipt',
    ],
    'learn': [
      'Find and assess learning resources',
      'Study the core concepts',
      'Work through examples or exercises',
      'Apply what you have learned in a small project',
      'Review and summarise key takeaways',
    ],
    'build': [
      'Define requirements and what "done" looks like',
      'Design the approach or architecture',
      'Implement the core functionality',
      'Test and fix issues',
      'Ship or share the result',
    ],
    'write': [
      'Outline structure and key points',
      'Research and gather references',
      'Write the first draft',
      'Revise and tighten the content',
      'Final proofread and publish',
    ],
    'plan': [
      'Clarify the objective and constraints',
      'Gather relevant information',
      'Identify options and trade-offs',
      'Make decisions and document them',
      'Communicate or execute the plan',
    ],
    'read': [
      'Acquire or locate the material',
      'Skim structure and key sections',
      'Read actively and take notes',
      'Review notes and highlights',
      'Reflect and record takeaways',
    ],
    'fix': [
      'Reproduce the problem and describe it clearly',
      'Investigate the root cause',
      'Design and implement the fix',
      'Verify the fix and check for regressions',
      'Document the resolution',
    ],
    'research': [
      'Define research questions',
      'Identify and assess sources',
      'Collect and organise findings',
      'Analyse and draw conclusions',
      'Summarise and share results',
    ],
    'launch': [
      'Define launch criteria and checklist',
      'Prepare all required materials',
      'Run final checks',
      'Execute the launch',
      'Monitor and follow up',
    ],
    'design': [
      'Define requirements and constraints',
      'Sketch initial concepts',
      'Create detailed design or prototype',
      'Gather feedback',
      'Refine and finalise',
    ],
    'exercise': [
      'Schedule sessions in your calendar',
      'Prepare equipment or environment',
      'Warm-up routine',
      'Main session',
      'Track and log progress',
    ],
    'fallback': [
      'Define what done looks like for this goal',
      'Break down the first concrete action',
      'Complete the first action',
      'Review progress and adjust if needed',
    ],
  };
}
