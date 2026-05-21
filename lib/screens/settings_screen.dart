import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/enums.dart';
import '../services/daily_reset_service.dart';
import '../services/display_preferences.dart';
import '../services/notification_service.dart';
import '../services/settings/llm_settings_service.dart';
import 'data_settings_screen.dart';
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
            title: 'Home screen widget',
            children: [
              _FocusWidgetShowAllGoalsTile(),
              _FocusWidgetLayoutTile(),
            ],
          ),
          _SettingsSection(
            title: 'Data',
            children: [
              _DataTile(),
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
    return ListTile(
      leading: const Icon(Icons.psychology_outlined),
      title: const Text('LLM configuration'),
      subtitle: Text(profile != null ? profile.displayName : 'Not configured'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LlmSettingsScreen()),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Home screen widget section
// ---------------------------------------------------------------------------

class _FocusWidgetShowAllGoalsTile extends StatelessWidget {
  const _FocusWidgetShowAllGoalsTile();

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<DisplayPreferences>();
    return SwitchListTile(
      secondary: const Icon(Icons.dashboard_outlined),
      title: const Text('Show all focused goals'),
      subtitle: const Text(
        'Display a row for every focused goal instead of only the top one',
      ),
      value: prefs.focusWidgetShowAllGoals,
      onChanged: prefs.setFocusWidgetShowAllGoals,
    );
  }
}

class _FocusWidgetLayoutTile extends StatelessWidget {
  const _FocusWidgetLayoutTile();

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<DisplayPreferences>();
    return ListTile(
      leading: const Icon(Icons.widgets_outlined),
      title: const Text('Widget layout'),
      subtitle: Text(
        'How much the resizable home-screen widget shows — '
        '${prefs.focusWidgetLayout.displayName.toLowerCase()}',
      ),
      onTap: () => _showLayoutPicker(context, prefs),
    );
  }

  void _showLayoutPicker(BuildContext context, DisplayPreferences prefs) {
    showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Widget layout'),
        children: [
          for (final layout in FocusLayout.values)
            ListTile(
              title: Text(layout.displayName),
              trailing: prefs.focusWidgetLayout == layout
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                prefs.setFocusWidgetLayout(layout);
                Navigator.pop(ctx);
              },
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Data section
// ---------------------------------------------------------------------------

class _DataTile extends StatelessWidget {
  const _DataTile();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.storage_outlined),
      title: const Text('Data'),
      subtitle: const Text('Backup, restore, archive and clear'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DataSettingsScreen()),
      ),
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
