import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'app_bottom_sheet.dart';

/// Result of the snooze picker.
///
/// [until] is the absolute wake-up time. [notify] is whether a wake-up
/// notification should be posted at that moment. The picker returns null
/// when the user dismisses without picking.
class SnoozeResult {
  final DateTime until;
  final bool notify;

  const SnoozeResult({required this.until, required this.notify});
}

/// Bottom sheet that lets the user pick when a subtask should wake up.
///
/// Layout:
///   • Quick-pick chips (15 min, 1 hour, this evening, tomorrow, next week)
///   • "Custom…" tile that opens a date+time picker
///   • A toggle for "Notify me when it's ready"
///
/// The picker is intentionally lightweight — the user is paused mid-task
/// and shouldn't have to wade through a calendar. Quick picks cover the
/// vast majority of use cases.
class SnoozePickerSheet extends StatefulWidget {
  /// Optional preselect — e.g. when re-opening the picker to change an
  /// existing snooze. Null defaults to "1 hour from now".
  final DateTime? initialUntil;
  final bool initialNotify;

  const SnoozePickerSheet({
    super.key,
    this.initialUntil,
    this.initialNotify = false,
  });

  /// Convenience wrapper that pops up the sheet and returns the user's
  /// choice (or null if dismissed).
  static Future<SnoozeResult?> show(
    BuildContext context, {
    DateTime? initialUntil,
    bool initialNotify = false,
  }) {
    return showModalBottomSheet<SnoozeResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SnoozePickerSheet(
        initialUntil: initialUntil,
        initialNotify: initialNotify,
      ),
    );
  }

  @override
  State<SnoozePickerSheet> createState() => _SnoozePickerSheetState();
}

class _SnoozePickerSheetState extends State<SnoozePickerSheet> {
  late DateTime _until;
  late bool _notify;
  // Tracks which quick-pick (if any) is currently selected so the UI can
  // highlight it. Null when the user has chosen a custom datetime.
  _Preset? _selectedPreset;

  @override
  void initState() {
    super.initState();
    _until = widget.initialUntil ?? _Preset.oneHour.compute();
    _notify = widget.initialNotify;
    _selectedPreset = widget.initialUntil == null ? _Preset.oneHour : null;
  }

  void _selectPreset(_Preset preset) {
    setState(() {
      _until = preset.compute();
      _selectedPreset = preset;
    });
  }

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _until.isAfter(now) ? _until : now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 2)),
    );
    if (pickedDate == null || !mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_until),
    );
    if (pickedTime == null || !mounted) return;
    setState(() {
      _until = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
      _selectedPreset = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppBottomSheet(
      title: 'Snooze this step',
      children: [
        Text(
          'Hide this step until later. The goal goes on hold while snoozed.',
          style: TextStyle(color: AppColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        // Quick-pick chips
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in _Preset.values)
              ChoiceChip(
                label: Text(preset.label),
                selected: _selectedPreset == preset,
                onSelected: (_) => _selectPreset(preset),
              ),
          ],
        ),
        const SizedBox(height: 12),
        // Custom date+time
        OutlinedButton.icon(
          icon: const Icon(Icons.calendar_today_outlined, size: 18),
          label: Text(
            _selectedPreset == null
                ? 'Custom · ${_formatAbsolute(_until)}'
                : 'Choose custom date & time',
          ),
          onPressed: _pickCustom,
        ),
        const SizedBox(height: 16),
        // Notify toggle
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Notify me when it wakes up'),
          subtitle: Text(
            'Posts a notification at the wake-up time.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          value: _notify,
          onChanged: (v) => setState(() => _notify = v),
        ),
        const SizedBox(height: 12),
        // Confirmation summary + actions
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
                  'Wakes ${_formatAbsolute(_until)}',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.strong,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: !_until.isAfter(DateTime.now())
                    ? null
                    : () => Navigator.of(context).pop(
                          SnoozeResult(until: _until, notify: _notify),
                        ),
                child: const Text('Snooze'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// "Today 18:30", "Tomorrow 09:00", "Wed 12 Aug 14:00", etc.
  static String _formatAbsolute(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dt.year, dt.month, dt.day);
    final diffDays = target.difference(today).inDays;
    final hhmm =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (diffDays == 0) return 'today at $hhmm';
    if (diffDays == 1) return 'tomorrow at $hhmm';
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final label = '${days[dt.weekday - 1]} ${dt.day} ${months[dt.month - 1]}';
    if (dt.year != now.year) return '$label ${dt.year} at $hhmm';
    return '$label at $hhmm';
  }
}

/// Common quick-pick presets for the snooze picker.
enum _Preset {
  fifteenMin,
  oneHour,
  thisEvening,
  tomorrowMorning,
  nextWeek;

  String get label => switch (this) {
        _Preset.fifteenMin => '15 min',
        _Preset.oneHour => '1 hour',
        _Preset.thisEvening => 'This evening',
        _Preset.tomorrowMorning => 'Tomorrow 9 am',
        _Preset.nextWeek => 'Next week',
      };

  /// Computes the absolute datetime this preset represents from "now".
  /// Encapsulating it here keeps the picker UI free of date arithmetic.
  DateTime compute() {
    final now = DateTime.now();
    switch (this) {
      case _Preset.fifteenMin:
        return now.add(const Duration(minutes: 15));
      case _Preset.oneHour:
        return now.add(const Duration(hours: 1));
      case _Preset.thisEvening:
        // 6 pm today — or 6 pm tomorrow if it's already past.
        final target = DateTime(now.year, now.month, now.day, 18);
        return target.isAfter(now)
            ? target
            : target.add(const Duration(days: 1));
      case _Preset.tomorrowMorning:
        // 9 am tomorrow.
        return DateTime(now.year, now.month, now.day + 1, 9);
      case _Preset.nextWeek:
        // 9 am one week from today.
        return DateTime(now.year, now.month, now.day + 7, 9);
    }
  }
}
