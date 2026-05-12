import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import '../models/goal.dart';
import '../services/goal_queries.dart';
import '../services/goal_service.dart';
import 'goal_detail_screen.dart';

// The Inbox tab — shows goals captured without any decomposition yet.
// Tapping an item navigates to the detail screen, where the user adds
// subtasks. As soon as the first subtask is added, Goal._recalculateStatus()
// flips the goal's status from `inbox` to `active`, so it leaves this list
// and shows up on the Goals tab instead.
class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // watch() makes this widget rebuild when the repository notifies listeners
    // (e.g. when a goal is added to the inbox, deleted, or promoted to active).
    final queries = context.watch<GoalQueries>();
    final items = queries.inbox;

    return Scaffold(
      appBar: AppBar(title: const Text('Inbox')),
      body: items.isEmpty ? const _EmptyState() : _InboxList(items: items),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 48, color: Colors.grey),
          SizedBox(height: 12),
          Text('Inbox is empty'),
          SizedBox(height: 4),
          Text(
            'Capture quick ideas here to process later',
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _InboxList extends StatelessWidget {
  final List<Goal> items;

  const _InboxList({required this.items});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) => _InboxTile(goal: items[index]),
    );
  }
}

class _InboxTile extends StatelessWidget {
  final Goal goal;

  const _InboxTile({required this.goal});

  @override
  Widget build(BuildContext context) {
    // read() — one-off lookup, no subscription. Use read() inside event
    // handlers and build paths that don't depend on changes to the value.
    final service = context.read<GoalService>();

    return Slidable(
      // ValueKey based on goalId tells Flutter "this widget represents goal X".
      // When the list rebuilds with the same key, Flutter reuses the same
      // widget element instead of disposing and re-creating it.
      key: ValueKey(goal.goalId),
      // endActionPane = revealed when swiping right-to-left (from end toward start)
      endActionPane: ActionPane(
        // BehindMotion = action sits behind the tile and is revealed as
        // the tile slides over it. Feels natural for destructive actions.
        motion: const BehindMotion(),
        // extentRatio = how much of the tile width the action pane occupies
        // when fully open. 0.25 means a quarter of the row.
        extentRatio: 0.25,
        children: [
          SlidableAction(
            onPressed: (_) => service.removeGoal(goal.goalId),
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            icon: Icons.delete_outline,
            label: 'Delete',
          ),
        ],
      ),
      child: ListTile(
        leading: const Icon(Icons.inbox_outlined, color: Colors.grey),
        title: Text(goal.title),
        // If the user captured a description it's worth surfacing here.
        // Falls back to a hint that nudges the user to process the item.
        subtitle: Text(
          goal.notes.isNotEmpty ? goal.notes : 'Tap to add subtasks',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
        // Reuse the detail screen — adding a subtask there will move
        // this goal out of the inbox automatically (see Goal.addSubTask).
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GoalDetailScreen(goalId: goal.goalId),
          ),
        ),
      ),
    );
  }
}
