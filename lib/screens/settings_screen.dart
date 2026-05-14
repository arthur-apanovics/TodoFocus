import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/backup_service.dart';
import '../services/daily_reset_service.dart';
import '../services/goal_repository.dart';
import '../services/notification_service.dart';
import '../services/settings/llm_settings_service.dart';
import 'llm_settings_screen.dart';

// Settings are organised into named sections. To add a new setting:
//   1. Add a ListTile (or custom widget) inside the relevant _SettingsSection.
//   2. For a sub-screen (e.g. LLM config), push a new route from onTap.
//   3. For a new category, add another _SettingsSection at the bottom.

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: const [
          _SettingsSection(
            title: 'AI Assistant',
            children: [
              _LlmConfigTile(),
            ],
          ),
          _SettingsSection(
            title: 'Daily Reset',
            children: [
              _DailyResetToggleTile(),
              _DailyResetTimeTile(),
              _MorningPromptToggleTile(),
              _MorningPromptTimeTile(),
              _UrgencyDaysTile(),
            ],
          ),
          _SettingsSection(
            title: 'Appearance',
            children: [
              _ComingSoonTile(
                icon: Icons.palette_outlined,
                title: 'Theme',
                subtitle: 'Accent colour and dark mode',
              ),
            ],
          ),
          _SettingsSection(
            title: 'Data',
            children: [
              _ExportTile(),
              _ImportTile(),
              _ClearDatabaseTile(),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
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
        ...children,
        const Divider(height: 1),
      ],
    );
  }
}

class _ComingSoonTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _ComingSoonTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const _ComingSoonBadge(),
    );
  }
}

class _ComingSoonBadge extends StatelessWidget {
  const _ComingSoonBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        'Soon',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AI Assistant section
// ---------------------------------------------------------------------------

class _LlmConfigTile extends StatelessWidget {
  const _LlmConfigTile();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<LlmSettingsService>();
    final profile = settings.activeProfile;
    final enabled = settings.isEnabled;
    return ListTile(
      leading: const Icon(Icons.psychology_outlined),
      title: const Text('LLM configuration'),
      subtitle: Text(
        enabled && profile != null
            ? '${profile.displayName} — enabled'
            : profile != null
                ? '${profile.displayName} — disabled'
                : 'Not configured',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LlmSettingsScreen()),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Data section
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
        const SnackBar(content: Text('Import failed — file could not be read')),
      );
    }
  }
}

class _ClearDatabaseTile extends StatelessWidget {
  const _ClearDatabaseTile();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(Icons.delete,
          color: Theme.of(context).colorScheme.error),
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
            onChanged: (v) =>
                setState(() => _confirmed = v.trim().toLowerCase() == 'delete'),
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
            disabledBackgroundColor:
                Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.4),
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

// ---------------------------------------------------------------------------
// Daily Reset section
// ---------------------------------------------------------------------------

class _DailyResetToggleTile extends StatelessWidget {
  const _DailyResetToggleTile();

  @override
  Widget build(BuildContext context) {
    final service = context.watch<DailyResetService>();
    return SwitchListTile(
      secondary: const Icon(Icons.restart_alt_outlined),
      title: const Text('Enable daily reset'),
      subtitle: const Text('Clears focus assignments at a set time each day'),
      value: service.resetEnabled,
      onChanged: service.setResetEnabled,
    );
  }
}

class _DailyResetTimeTile extends StatelessWidget {
  const _DailyResetTimeTile();

  @override
  Widget build(BuildContext context) {
    final service = context.watch<DailyResetService>();
    if (!service.resetEnabled) return const SizedBox.shrink();
    final t = service.resetTime;
    return ListTile(
      leading: const Icon(Icons.access_time_outlined),
      title: const Text('Reset time'),
      subtitle: Text(t.format(context)),
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: t,
          helpText: 'Choose when focus assignments reset',
        );
        if (picked != null) await service.setResetTime(picked);
      },
    );
  }
}

class _MorningPromptToggleTile extends StatelessWidget {
  const _MorningPromptToggleTile();

  @override
  Widget build(BuildContext context) {
    final service = context.watch<DailyResetService>();
    if (!service.resetEnabled) return const SizedBox.shrink();
    return SwitchListTile(
      secondary: const Icon(Icons.notifications_outlined),
      title: const Text('Morning prompt'),
      subtitle: const Text(
        'Daily notification reminding you to assign tasks for the day',
      ),
      value: service.morningPromptEnabled,
      onChanged: (value) async {
        final notif = context.read<NotificationService>();
        await service.setMorningPromptEnabled(value);
        if (value) {
          final t = service.morningPromptTime;
          await notif.scheduleMorningPrompt(t.hour, t.minute);
        } else {
          await notif.cancelMorningPrompt();
        }
      },
    );
  }
}

class _MorningPromptTimeTile extends StatelessWidget {
  const _MorningPromptTimeTile();

  @override
  Widget build(BuildContext context) {
    final service = context.watch<DailyResetService>();
    if (!service.resetEnabled || !service.morningPromptEnabled) {
      return const SizedBox.shrink();
    }
    final t = service.morningPromptTime;
    return ListTile(
      leading: const Icon(Icons.wb_sunny_outlined),
      title: const Text('Prompt time'),
      subtitle: Text(t.format(context)),
      onTap: () async {
        final notif = context.read<NotificationService>();
        final picked = await showTimePicker(
          context: context,
          initialTime: t,
          helpText: 'Choose when to receive the morning prompt',
        );
        if (picked != null) {
          await service.setMorningPromptTime(picked);
          await notif.scheduleMorningPrompt(picked.hour, picked.minute);
        }
      },
    );
  }
}

class _UrgencyDaysTile extends StatelessWidget {
  const _UrgencyDaysTile();

  @override
  Widget build(BuildContext context) {
    final service = context.watch<DailyResetService>();
    return ListTile(
      leading: const Icon(Icons.flag_outlined),
      title: const Text('Urgency window'),
      subtitle: Text(
        'Goals due within ${service.urgencyDays} day${service.urgencyDays == 1 ? '' : 's'} are prioritised',
      ),
      onTap: () => _showUrgencyDialog(context, service),
    );
  }

  void _showUrgencyDialog(BuildContext context, DailyResetService service) {
    var days = service.urgencyDays;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Urgency window'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$days day${days == 1 ? '' : 's'}',
                style: Theme.of(ctx).textTheme.headlineSmall,
              ),
              Slider(
                value: days.toDouble(),
                min: 1,
                max: 14,
                divisions: 13,
                label: '$days',
                onChanged: (v) => setState(() => days = v.round()),
              ),
              Text(
                'Goals with a deadline within this many days will be sorted to the top.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                service.setUrgencyDays(days);
                Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
