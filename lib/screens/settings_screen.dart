import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/enums.dart';
import '../services/daily_reset_service.dart';
import '../services/display_preferences.dart';
import '../services/focus_list_service.dart';
import '../services/goal_repository.dart';
import '../services/notification_service.dart';
import '../services/settings/llm_settings_service.dart';
import '../services/theme_controller.dart';
import '../theme/app_theme.dart';
import 'archived_goals_screen.dart';
import 'data_settings_screen.dart';
import 'llm_generation_screen.dart';
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
              _LlmConnectionTile(),
              _LlmGenerationTile(),
            ],
          ),
          _SettingsSection(
            title: 'Daily Reset',
            children: [
              _DailyResetToggleTile(),
              _DailyResetTimeTile(),
              _MorningPromptToggleTile(),
            ],
          ),
          _SettingsSection(
            title: 'Appearance',
            children: [
              _ThemeModeTile(),
              _ThemeColorTile(),
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
              _ArchivedGoalsTile(),
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

// ---------------------------------------------------------------------------
// Appearance section
// ---------------------------------------------------------------------------

class _ThemeModeTile extends StatelessWidget {
  const _ThemeModeTile();

  static String _label(ThemeMode mode) => switch (mode) {
    ThemeMode.system => 'Follow system',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ThemeController>();
    return ListTile(
      leading: const Icon(Icons.brightness_6_outlined),
      title: const Text('Appearance'),
      subtitle: Text(_label(controller.mode)),
      onTap: () => showDialog<void>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Appearance'),
          children: [
            for (final mode in ThemeMode.values)
              ListTile(
                title: Text(_label(mode)),
                trailing: controller.mode == mode
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  controller.setMode(mode);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ThemeColorTile extends StatelessWidget {
  const _ThemeColorTile();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ThemeController>();
    return ListTile(
      leading: const Icon(Icons.palette_outlined),
      title: const Text('Accent colour'),
      subtitle: Text(controller.color.displayName),
      trailing: _ColorSwatch(color: controller.color.seed),
      onTap: () => showDialog<void>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Accent colour'),
          children: [
            for (final color in AppThemeColor.values)
              ListTile(
                leading: _ColorSwatch(color: color.seed),
                title: Text(color.displayName),
                trailing: controller.color == color
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  controller.setColor(color);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  final Color color;

  const _ColorSwatch({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AI Assistant section
// ---------------------------------------------------------------------------

/// Provider + endpoint + API key + sampling + timeout + debug.
/// "How the app talks to the model."
class _LlmConnectionTile extends StatelessWidget {
  const _LlmConnectionTile();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<LlmSettingsService>();
    final profile = settings.activeProfile;
    return ListTile(
      leading: const Icon(Icons.cable_outlined),
      title: const Text('Connection'),
      subtitle: Text(profile != null ? profile.displayName : 'Not configured'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LlmConnectionScreen()),
      ),
    );
  }
}

/// Icon toggle + system prompt + difficulty subtask-count ranges.
/// "What the model is asked to produce."
class _LlmGenerationTile extends StatelessWidget {
  const _LlmGenerationTile();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<LlmSettingsService>();
    return ListTile(
      leading: const Icon(Icons.auto_awesome_outlined),
      title: const Text('Generation'),
      subtitle: Text(
        settings.generateEmojis
            ? 'Goal icons on · custom prompt and difficulty ranges'
            : 'Goal icons off · custom prompt and difficulty ranges',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LlmGenerationScreen()),
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
        // Compact is intentionally excluded — on the home-screen widget the
        // header-only variant collapses to an unactionable rectangle (no
        // completion button to tap, unlike the in-app Focus tab's compact
        // mode). Single step is the practical floor.
        children: [
          for (final layout in const [
            FocusLayout.current,
            FocusLayout.currentPlus2,
            FocusLayout.currentPlus4,
          ])
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

class _ArchivedGoalsTile extends StatelessWidget {
  const _ArchivedGoalsTile();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.archive_outlined),
      title: const Text('Archived goals'),
      subtitle: const Text('Browse, restore or delete archived goals'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ArchivedGoalsScreen()),
      ),
    );
  }
}

class _DataTile extends StatelessWidget {
  const _DataTile();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.storage_outlined),
      title: const Text('Data'),
      subtitle: const Text('Backup, restore, sample data and clear'),
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
      title: const Text('Plan-your-day reminder'),
      subtitle: const Text(
        'Show a reminder in the focus notification when nothing is assigned',
      ),
      value: service.morningPromptEnabled,
      onChanged: (value) async {
        final notif = context.read<NotificationService>();
        final focus = context.read<FocusListService>();
        final repo = context.read<GoalRepository>();
        await service.setMorningPromptEnabled(value);
        // Reflect the toggle immediately: re-render the persistent
        // notification so the empty-state reminder appears / disappears.
        await notif.update(
          focus.resolveGroups(repo),
          showEmptyPrompt: value,
        );
      },
    );
  }
}

