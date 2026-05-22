import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import '../models/goal.dart';
import '../services/goal_queries.dart';
import '../services/goal_service.dart';
import '../theme/app_palette.dart';

/// Standalone screen listing every archived goal.
///
/// Lifted out of [DataSettingsScreen]'s "Archive" section so that the
/// archive (a frequently visited list of past goals) is one tap away from
/// Settings, instead of buried under "Data" alongside the backup/danger
/// zone controls.
class ArchivedGoalsScreen extends StatelessWidget {
  const ArchivedGoalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final archived = context.watch<GoalQueries>().archivedGoals;
    return Scaffold(
      appBar: AppBar(title: const Text('Archived goals')),
      body: archived.isEmpty
          ? const _EmptyArchive()
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: archived.length,
                    itemBuilder: (_, i) => _ArchiveTile(goal: archived[i]),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: _ClearArchiveButton(),
                ),
              ],
            ),
    );
  }
}

class _EmptyArchive extends StatelessWidget {
  const _EmptyArchive();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.archive_outlined,
              size: 48,
              color: context.palette.muted,
            ),
            const SizedBox(height: 12),
            Text(
              'No archived goals',
              style: TextStyle(color: context.palette.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArchiveTile extends StatelessWidget {
  final Goal goal;

  const _ArchiveTile({required this.goal});

  @override
  Widget build(BuildContext context) {
    final service = context.read<GoalService>();
    return Slidable(
      key: ValueKey(goal.goalId),
      // Swipe right → Restore
      startActionPane: ActionPane(
        motion: const BehindMotion(),
        extentRatio: 0.28,
        children: [
          SlidableAction(
            onPressed: (_) => service.restoreGoal(goal.goalId),
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            icon: Icons.restore_outlined,
            label: 'Restore',
          ),
        ],
      ),
      // Swipe left → Delete
      endActionPane: ActionPane(
        motion: const BehindMotion(),
        extentRatio: 0.28,
        children: [
          SlidableAction(
            onPressed: (_) => service.removeGoal(goal.goalId),
            backgroundColor: context.palette.destructive,
            foregroundColor: context.palette.onDestructive,
            icon: Icons.delete_outline,
            label: 'Delete',
          ),
        ],
      ),
      child: ListTile(
        leading: const Icon(Icons.archive_outlined),
        title: Text(goal.title),
        subtitle: Text(
          goal.subtasks.isEmpty
              ? 'No subtasks'
              : '${goal.completedSubtaskCount} of ${goal.subtasks.length} complete',
        ),
      ),
    );
  }
}

class _ClearArchiveButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _confirm(context),
        icon: const Icon(Icons.delete_sweep_outlined),
        label: const Text('Delete all archived goals'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.error,
          side: BorderSide(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final service = context.read<GoalService>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all archived goals?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (confirmed == true) service.clearArchive();
  }
}
