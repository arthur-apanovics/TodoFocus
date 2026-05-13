import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/goal_repository.dart';
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
              ? () {
                  widget.repo.clear();
                  Navigator.pop(context);
                }
              : null,
          child: const Text('Delete everything'),
        ),
      ],
    );
  }
}
