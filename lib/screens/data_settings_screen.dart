import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/enums.dart';
import '../services/backup_service.dart';
import '../services/focus_list_service.dart';
import '../services/goal_repository.dart';
import '../services/goal_service.dart';
import '../services/google_drive_backup_service.dart';
import '../services/sample_data.dart';
import 'google_drive_backup_screen.dart';

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
    return CustomScrollView(
      slivers: [
        // ── Google Drive ─────────────────────────────────────────────────────
        _SliverSectionHeader(title: 'Google Drive'),
        const SliverToBoxAdapter(child: _GoogleDriveTile()),
        const SliverToBoxAdapter(child: Divider(height: 1)),

        // ── Local backup ─────────────────────────────────────────────────────
        _SliverSectionHeader(title: 'Local backup'),
        const SliverToBoxAdapter(child: _ExportTile()),
        const SliverToBoxAdapter(child: _ImportTile()),
        const SliverToBoxAdapter(child: Divider(height: 1)),

        // ── Developer ────────────────────────────────────────────────────────
        _SliverSectionHeader(title: 'Developer'),
        const SliverToBoxAdapter(child: _LoadSampleDataTile()),
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
// Google Drive tile
// ---------------------------------------------------------------------------

class _GoogleDriveTile extends StatelessWidget {
  const _GoogleDriveTile();

  @override
  Widget build(BuildContext context) {
    final service = context.watch<GoogleDriveBackupService>();
    final user = service.currentUser;
    final lastBackup = service.lastBackupAt;

    final String subtitle;
    if (!service.isSignedIn) {
      subtitle = 'Not signed in';
    } else if (lastBackup == null) {
      subtitle = user!.email;
    } else {
      final diff = DateTime.now().difference(lastBackup);
      final age = diff.inSeconds < 60
          ? 'just now'
          : diff.inMinutes < 60
              ? '${diff.inMinutes}m ago'
              : diff.inHours < 24
                  ? '${diff.inHours}h ago'
                  : '${diff.inDays}d ago';
      subtitle = '${user!.email} · last backup $age';
    }

    return ListTile(
      leading: const Icon(Icons.cloud_outlined),
      title: const Text('Google Drive backup'),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const GoogleDriveBackupScreen()),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Local backup tiles (moved from settings_screen.dart)
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
// Developer
// ---------------------------------------------------------------------------

class _LoadSampleDataTile extends StatelessWidget {
  const _LoadSampleDataTile();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.science_outlined),
      title: const Text('Load sample data'),
      subtitle: const Text('Adds 28 goals covering every state and difficulty'),
      onTap: () => _confirm(context),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Load sample data?'),
        content: const Text(
          'This adds 28 sample goals in various states (active, completed, '
          'archived, inbox) to your current data. Existing goals are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Load'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final service = context.read<GoalService>();
    final focus = context.read<FocusListService>();
    final repo = context.read<GoalRepository>();
    final goals = SampleData.build();
    for (final goal in goals) {
      service.addGoal(goal);
    }

    // Seed today's focus with the first two active goals (fully focused)
    // so the Focus tab isn't empty after loading samples.
    final activeWithPending = goals
        .where((g) =>
            g.status == GoalStatus.active &&
            g.subtasks.any((s) => s.state == SubTaskState.pending))
        .take(2)
        .toList();
    for (final goal in activeWithPending) {
      await focus.focusGoalFully(goal.goalId, repo);
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added ${goals.length} sample goals')),
    );
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
