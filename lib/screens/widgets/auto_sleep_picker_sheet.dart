import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_colors.dart';
import 'app_bottom_sheet.dart';

/// Bottom sheet that lets the user configure how long a queued subtask
/// should sleep when it becomes the goal's current step.
///
/// Mental model: "When this step is next up, give me X delay before I have
/// to act on it." Distinct from the regular snooze flow because there's
/// nothing to snooze *yet* — the subtask is queued behind earlier steps.
///
/// Result semantics:
///   • [AutoSleepResult.set]   — user picked a non-zero duration.
///   • [AutoSleepResult.cleared] — user removed an existing auto-sleep.
///   • `null` from `show()` — user dismissed without committing.
class AutoSleepPickerSheet extends StatefulWidget {
  final Duration? initial;

  const AutoSleepPickerSheet({super.key, this.initial});

  static Future<AutoSleepResult?> show(
    BuildContext context, {
    Duration? initial,
  }) {
    return showModalBottomSheet<AutoSleepResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AutoSleepPickerSheet(initial: initial),
    );
  }

  @override
  State<AutoSleepPickerSheet> createState() => _AutoSleepPickerSheetState();
}

class AutoSleepResult {
  final Duration? duration;
  final bool cleared;

  const AutoSleepResult.set(Duration d)
      : duration = d,
        cleared = false;
  const AutoSleepResult.cleared()
      : duration = null,
        cleared = true;
}

class _AutoSleepPickerSheetState extends State<AutoSleepPickerSheet> {
  /// Selected preset (null when using the manual value field).
  _AutoSleepPreset? _preset;

  /// Manual value + unit, used when the user picks "Custom".
  int _customValue = 1;
  _DurationUnit _customUnit = _DurationUnit.day;

  late final TextEditingController _customController;

  @override
  void initState() {
    super.initState();
    _customController =
        TextEditingController(text: _customValue.toString());
    final init = widget.initial;
    if (init == null) {
      _preset = _AutoSleepPreset.oneDay;
    } else {
      // Pick the closest preset; fall back to Custom + computed value/unit.
      final matched = _AutoSleepPreset.values
          .firstWhere(
            (p) => p.duration == init,
            orElse: () => _AutoSleepPreset.custom,
          );
      _preset = matched;
      if (matched == _AutoSleepPreset.custom) {
        final (v, u) = _splitDuration(init);
        _customValue = v;
        _customUnit = u;
        _customController.text = v.toString();
      }
    }
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  Duration get _resolvedDuration {
    if (_preset != _AutoSleepPreset.custom) {
      return _preset?.duration ?? _AutoSleepPreset.oneDay.duration;
    }
    return _customUnit.toDuration(_customValue);
  }

  @override
  Widget build(BuildContext context) {
    final resolved = _resolvedDuration;
    final hasInitial = widget.initial != null;

    return AppBottomSheet(
      title: 'Auto-sleep this step',
      children: [
        Text(
          'When this step becomes active, automatically snooze it for the '
          'chosen duration. Useful for steps that need a waiting period '
          '(e.g. "check email 3 days later").',
          style: TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 16),

        // Preset chips.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in _AutoSleepPreset.values)
              ChoiceChip(
                label: Text(p.label),
                selected: _preset == p,
                showCheckmark: false,
                onSelected: (_) => setState(() => _preset = p),
              ),
          ],
        ),
        const SizedBox(height: 16),

        // Custom form (visible only when Custom is selected).
        if (_preset == _AutoSleepPreset.custom)
          Row(
            children: [
              SizedBox(
                width: 64,
                child: TextField(
                  controller: _customController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (raw) {
                    final n = int.tryParse(raw);
                    if (n != null && n > 0) {
                      setState(() => _customValue = n);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<_DurationUnit>(
                value: _customUnit,
                onChanged: (v) =>
                    v == null ? null : setState(() => _customUnit = v),
                items: [
                  for (final u in _DurationUnit.values)
                    DropdownMenuItem(value: u, child: Text(u.label)),
                ],
              ),
            ],
          ),

        const SizedBox(height: 12),
        // Resolved-duration preview.
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.successSurface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.bedtime_outlined, color: AppColors.accent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Sleeps for ${_humanise(resolved)} when activated',
                  style: TextStyle(fontSize: 13, color: AppColors.strong),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Actions
        Row(
          children: [
            if (hasInitial)
              TextButton.icon(
                onPressed: () => Navigator.of(context)
                    .pop(const AutoSleepResult.cleared()),
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('Clear'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.destructive,
                ),
              ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: resolved.inSeconds <= 0
                  ? null
                  : () => Navigator.of(context)
                      .pop(AutoSleepResult.set(resolved)),
              child: const Text('Apply'),
            ),
          ],
        ),
      ],
    );
  }

  /// Render a Duration as "3 days", "1 hour", "45 min". Picks the largest
  /// unit that yields a whole number; falls back to minutes.
  static String _humanise(Duration d) {
    if (d.inDays >= 1 && d.inHours % 24 == 0) {
      final n = d.inDays;
      return '$n day${n == 1 ? '' : 's'}';
    }
    if (d.inHours >= 1 && d.inMinutes % 60 == 0) {
      final n = d.inHours;
      return '$n hour${n == 1 ? '' : 's'}';
    }
    final n = d.inMinutes;
    return '$n minute${n == 1 ? '' : 's'}';
  }

  /// Splits a Duration into the largest whole-unit (value, unit) pair.
  static (int, _DurationUnit) _splitDuration(Duration d) {
    if (d.inDays >= 1 && d.inHours % 24 == 0) {
      return (d.inDays, _DurationUnit.day);
    }
    if (d.inHours >= 1 && d.inMinutes % 60 == 0) {
      return (d.inHours, _DurationUnit.hour);
    }
    return (d.inMinutes, _DurationUnit.minute);
  }
}

/// Quick presets surfaced as chips. The "custom" entry reveals the value +
/// unit form so any duration can be configured.
enum _AutoSleepPreset {
  oneHour,
  threeHours,
  oneDay,
  threeDays,
  oneWeek,
  custom;

  String get label => switch (this) {
        _AutoSleepPreset.oneHour => '1 hour',
        _AutoSleepPreset.threeHours => '3 hours',
        _AutoSleepPreset.oneDay => '1 day',
        _AutoSleepPreset.threeDays => '3 days',
        _AutoSleepPreset.oneWeek => '1 week',
        _AutoSleepPreset.custom => 'Custom',
      };

  Duration get duration => switch (this) {
        _AutoSleepPreset.oneHour => const Duration(hours: 1),
        _AutoSleepPreset.threeHours => const Duration(hours: 3),
        _AutoSleepPreset.oneDay => const Duration(days: 1),
        _AutoSleepPreset.threeDays => const Duration(days: 3),
        _AutoSleepPreset.oneWeek => const Duration(days: 7),
        // "custom" has no fixed duration — handled separately.
        _AutoSleepPreset.custom => const Duration(days: 1),
      };
}

enum _DurationUnit {
  minute,
  hour,
  day,
  week;

  String get label => switch (this) {
        _DurationUnit.minute => 'minutes',
        _DurationUnit.hour => 'hours',
        _DurationUnit.day => 'days',
        _DurationUnit.week => 'weeks',
      };

  Duration toDuration(int n) => switch (this) {
        _DurationUnit.minute => Duration(minutes: n),
        _DurationUnit.hour => Duration(hours: n),
        _DurationUnit.day => Duration(days: n),
        _DurationUnit.week => Duration(days: n * 7),
      };
}
