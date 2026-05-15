import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import '../models/goal.dart';
import '../services/backup_service.dart';
import '../services/goal_queries.dart';
import '../services/goal_repository.dart';
import '../services/goal_service.dart';
import '../theme/app_colors.dart';

class DataSettingsScreen extends StatelessWidget {
  const DataSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Data')),
      body: const _DataBody(),
    );
  }
}

class _DataBody extends StatelessWidget {
  const _DataBody();

  @override
  Widget build(BuildContext context) {
    final archived = context.watch<GoalQueries>().archivedGoals;

    return CustomScrollView(
      slivers: [
        // ── Archive ──────────────────────────────────────────────────────────
        _SliverSectionHeader(title: 'Archive'),
        if (archived.isEmpty)
          const SliverToBoxAdapter(child: _EmptyArchive())
        else ...[
          SliverList.builder(
            itemCount: archived.length,
            itemBuilder: (ctx, i) => _ArchiveTile(goal: archived[i]),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: _ClearArchiveButton(),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: Divider(height: 1)),

        // ── Backup ───────────────────────────────────────────────────────────
        _SliverSectionHeader(title: 'Backup'),
        const SliverToBoxAdapter(child: _ExportTile()),
        const SliverToBoxAdapter(child: _ImportTile()),
        const SliverToBoxAdapter(child: Divider(height: 1)),

        // ── Danger zone ──────────────────────────────────────────────────────
        _SliverSectionHeader(title: 'Danger zone'),
        const SliverToBoxAdapter(child: _ClearDatabaseTile()),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

class _SliverSectionHeader extends StatelessWidget {
  final String title;

  const _SliverSectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(
          title,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Archive widgets
// ---------------------------------------------------------------------------

class _EmptyArchive extends StatelessWidget {
  const _EmptyArchive();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Text(
        'No archived goals',
        style: TextStyle(color: AppColors.muted),
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
            backgroundColor: AppColors.destructive,
            foregroundColor: AppColors.onDestructive,
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
    return OutlinedButton.icon(
      onPressed: () => _confirm(context),
      icon: const Icon(Icons.delete_sweep_outlined),
      label: const Text('Delete all archived goals'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.error,
        side: BorderSide(color: Theme.of(context).colorScheme.error),
      ),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final service = context.read<GoalService>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete all archived goals?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (confirmed == true) service.clearArchive();
  }
}

// ---------------------------------------------------------------------------
// Backup tiles (moved from settings_screen.dart)
// ---------------------------------------------------------------------------

class _ExportTile extends StatelessWidget {
  const _ExportTile();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.upload_outlined),
      title: const Text('Export backup'),
      subtitle: const Text('Save all goals and settings to a file'),
      onTap: () => _export(context),
    );
  }

  Future<void> _export(BuildContext context) async {
    final backup = context.read<BackupService>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final saved = await backup.export();
      if (saved) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Backup saved')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }
}

class _ImportTile extends StatelessWidget {
  const _ImportTile();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.download_outlined),
      title: const Text('Import backup'),
      subtitle: const Text('Restore goals and settings from a file'),
      onTap: () => _import(context),
    );
  }

  Future<void> _import(BuildContext context) async {
    final backup = context.read<BackupService>();
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restore from backup?'),
        content: const Text(
          'This will replace all current goals and restore your LLM settings. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final result = await backup.import();
      if (result == null) return;
      final msg = result.skipped == 0
          ? 'Restored ${result.imported} goals'
          : 'Restored ${result.imported} goals (${result.skipped} skipped)';
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    } on FormatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
            content: Text('Import failed — file could not be read')),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Danger zone
// ---------------------------------------------------------------------------

class _ClearDatabaseTile extends StatelessWidget {
  const _ClearDatabaseTile();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading:
          Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
      title: Text(
        'Clear all data',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
      subtitle: const Text('Permanently deletes all goals and subtasks'),
      onTap: () => _showConfirmDialog(context),
    );
  }

  Future<void> _showConfirmDialog(BuildContext context) async {
    final repo = context.read<GoalRepository>();
    await showDialog<void>(
      context: context,
      builder: (_) => _ClearConfirmDialog(repo: repo),
    );
  }
}

class _ClearConfirmDialog extends StatefulWidget {
  final GoalRepository repo;

  const _ClearConfirmDialog({required this.repo});

  @override
  State<_ClearConfirmDialog> createState() => _ClearConfirmDialogState();
}

class _ClearConfirmDialogState extends State<_ClearConfirmDialog> {
  final _controller = TextEditingController();
  bool _confirmed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Clear all data?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This will permanently delete every goal and subtask. '
            'Type "delete" to confirm.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.none,
            decoration: const InputDecoration(
              hintText: 'delete',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(
                () => _confirmed = v.trim().toLowerCase() == 'delete'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
            disabledBackgroundColor: Theme.of(context)
                .colorScheme
                .errorContainer
                .withValues(alpha: 0.4),
          ),
          onPressed: _confirmed
              ? () async {
                  final nav = Navigator.of(context);
                  await widget.repo.clear();
                  if (mounted) nav.pop();
                }
              : null,
          child: const Text('Delete everything'),
        ),
      ],
    );
  }
}
