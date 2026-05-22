import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/enums.dart';
import '../../models/recurrence.dart';
import '../../theme/app_palette.dart';
import 'app_bottom_sheet.dart';

/// Bottom sheet for configuring a [Goal]'s recurrence pattern.
///
/// The picker exposes three user-visible frequencies — "Every N days" (which
/// covers daily as N=1), "Weekly" (multi-select weekday chips), and
/// "Monthly" (calendar-grid day picker). The legacy [RecurrenceFrequency.daily]
/// enum value is still understood when reading old data but is never offered
/// as a selectable chip; new selections use `Recurrence.everyNDays(1)` for
/// the daily case.
///
/// Returns a [RecurrencePickerResult] that distinguishes:
///   • Apply with a new recurrence
///   • Clear an existing recurrence
///   • Cancel (null from `show()`)
class RecurrencePickerSheet extends StatefulWidget {
  final Recurrence? initial;

  const RecurrencePickerSheet({super.key, this.initial});

  static Future<RecurrencePickerResult?> show(
    BuildContext context, {
    Recurrence? initial,
  }) {
    return showModalBottomSheet<RecurrencePickerResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => RecurrencePickerSheet(initial: initial),
    );
  }

  @override
  State<RecurrencePickerSheet> createState() => _RecurrencePickerSheetState();
}

/// Picker outcome.
///
/// • [RecurrencePickerResult.apply] — user picked a new recurrence.
/// • [RecurrencePickerResult.clear] — user removed the existing recurrence.
/// • A null result from [RecurrencePickerSheet.show] means the user
///   dismissed without committing either.
class RecurrencePickerResult {
  final Recurrence? recurrence;
  final bool cleared;

  const RecurrencePickerResult.apply(Recurrence r)
      : recurrence = r,
        cleared = false;
  const RecurrencePickerResult.clear()
      : recurrence = null,
        cleared = true;
}

/// User-visible frequency choices. Note this is a *picker concept*, not the
/// underlying [RecurrenceFrequency] — it deliberately drops the legacy
/// "daily" entry in favour of "Every N days" with N=1.
enum _PickerKind { everyN, weekly, monthly }

class _RecurrencePickerSheetState extends State<RecurrencePickerSheet> {
  late _PickerKind _kind;

  // Per-kind form state. Kept across kind changes so the user can flip
  // chips back and forth without losing their inputs.
  Set<int> _weeklyDays = {DateTime.monday};
  int _everyN = 1;
  int _dayOfMonth = 1;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init == null) {
      // Default to "Every N days" with N=1, which is the new canonical daily.
      _kind = _PickerKind.everyN;
      _everyN = 1;
    } else {
      switch (init.frequency) {
        case RecurrenceFrequency.daily:
          // Legacy daily → render as Every N days, N=1
          _kind = _PickerKind.everyN;
          _everyN = 1;
        case RecurrenceFrequency.everyNDays:
          _kind = _PickerKind.everyN;
          _everyN = init.everyNDays ?? 1;
        case RecurrenceFrequency.weeklyDays:
          _kind = _PickerKind.weekly;
          _weeklyDays = {...?init.daysOfWeek};
        case RecurrenceFrequency.monthly:
          _kind = _PickerKind.monthly;
          _dayOfMonth = init.dayOfMonth ?? 1;
      }
    }
  }

  Recurrence? _buildRecurrence() {
    switch (_kind) {
      case _PickerKind.everyN:
        return Recurrence.everyNDays(_everyN);
      case _PickerKind.weekly:
        if (_weeklyDays.isEmpty) return null;
        return Recurrence.weeklyDays(_weeklyDays);
      case _PickerKind.monthly:
        return Recurrence.monthly(_dayOfMonth);
    }
  }

  @override
  Widget build(BuildContext context) {
    // `preview` and `apply` are captured once per build. Defining `apply`
    // as a local variable (non-nullable, when preview is non-null) keeps
    // the onPressed closure type-safe without needing `!` assertions.
    final preview = _buildRecurrence();

    return AppBottomSheet(
      title: 'Repeat this goal',
      children: [
        Text(
          'When the next occurrence arrives, every subtask resets so you can '
          'do the goal again. The previous cycle is summarised on the goal '
          'so you can build on it.',
          style: TextStyle(color: context.palette.muted, fontSize: 13),
        ),
        const SizedBox(height: 16),

        // Kind selector
        _KindSelector(
          selected: _kind,
          onChanged: (k) => setState(() => _kind = k),
        ),
        const SizedBox(height: 16),

        // Kind-specific form
        _form(),

        const SizedBox(height: 12),
        // Live preview chip
        if (preview != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.palette.successSurface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.repeat, color: context.palette.accent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    preview.label,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.palette.strong,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),

        // Actions
        Row(
          children: [
            if (widget.initial != null)
              TextButton.icon(
                onPressed: () => Navigator.of(context).pop(
                  const RecurrencePickerResult.clear(),
                ),
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('Clear'),
                style: TextButton.styleFrom(
                  foregroundColor: context.palette.destructive,
                ),
              ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              // Capturing `preview` in a local variable defeats any
              // closure-promotion edge case and makes the null-guard explicit.
              onPressed: preview == null
                  ? null
                  : () {
                      Navigator.of(context).pop(
                        RecurrencePickerResult.apply(preview),
                      );
                    },
              child: const Text('Apply'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _form() {
    switch (_kind) {
      case _PickerKind.everyN:
        return _NumberStepper(
          label: 'Every',
          suffix: _everyN == 1 ? 'day' : 'days',
          value: _everyN,
          min: 1,
          max: 60,
          onChanged: (v) => setState(() => _everyN = v),
        );
      case _PickerKind.weekly:
        return _WeekdayChips(
          selected: _weeklyDays,
          onChanged: (s) => setState(() => _weeklyDays = s),
        );
      case _PickerKind.monthly:
        return _DayOfMonthGrid(
          selected: _dayOfMonth,
          onChanged: (v) => setState(() => _dayOfMonth = v),
        );
    }
  }
}

// ── Kind selector ───────────────────────────────────────────────────────────

class _KindSelector extends StatelessWidget {
  final _PickerKind selected;
  final ValueChanged<_PickerKind> onChanged;

  const _KindSelector({required this.selected, required this.onChanged});

  String _label(_PickerKind k) => switch (k) {
        _PickerKind.everyN => 'Every N days',
        _PickerKind.weekly => 'Weekly',
        _PickerKind.monthly => 'Monthly',
      };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final k in _PickerKind.values)
          ChoiceChip(
            label: Text(_label(k)),
            selected: selected == k,
            // showCheckmark: false avoids the layout shift caused by the
            // default leading tick icon appearing when a chip is selected.
            // Selection is communicated through the chip's filled background.
            showCheckmark: false,
            onSelected: (_) => onChanged(k),
          ),
      ],
    );
  }
}

// ── Weekly: weekday filter chips ────────────────────────────────────────────

class _WeekdayChips extends StatelessWidget {
  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;

  const _WeekdayChips({required this.selected, required this.onChanged});

  static const _labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 1; i <= 7; i++)
          FilterChip(
            label: Text(_labels[i - 1]),
            selected: selected.contains(i),
            showCheckmark: false, // see _KindSelector
            onSelected: (on) {
              final next = {...selected};
              if (on) {
                next.add(i);
              } else {
                next.remove(i);
              }
              onChanged(next);
            },
          ),
      ],
    );
  }
}

// ── Every N: ± stepper ──────────────────────────────────────────────────────

class _NumberStepper extends StatelessWidget {
  final String label;
  final String suffix;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _NumberStepper({
    required this.label,
    required this.suffix,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 12),
        IconButton.outlined(
          icon: const Icon(Icons.remove),
          onPressed: value > min ? () => onChanged(value - 1) : null,
          visualDensity: VisualDensity.compact,
        ),
        SizedBox(
          width: 40,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        IconButton.outlined(
          icon: const Icon(Icons.add),
          onPressed: value < max ? () => onChanged(value + 1) : null,
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: 8),
        Text(suffix, style: const TextStyle(fontSize: 14)),
      ],
    );
  }
}

// ── Monthly: 31-cell calendar-style grid + manual entry ─────────────────────

/// Calendar-style picker for day-of-month, plus a numeric input field as a
/// fallback for users who prefer typing.
///
/// The grid is the primary UX — visually it mirrors the layout users
/// already know from date pickers, so tapping "the 15th" is one gesture.
/// The text input below is a small, intentional escape hatch for
/// accessibility (screen readers + physical keyboards) and quick entry.
class _DayOfMonthGrid extends StatefulWidget {
  final int selected;
  final ValueChanged<int> onChanged;

  const _DayOfMonthGrid({required this.selected, required this.onChanged});

  @override
  State<_DayOfMonthGrid> createState() => _DayOfMonthGridState();
}

class _DayOfMonthGridState extends State<_DayOfMonthGrid> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.selected.toString());
  }

  @override
  void didUpdateWidget(_DayOfMonthGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync the input when the grid changes the selection.
    if (oldWidget.selected != widget.selected) {
      final str = widget.selected.toString();
      if (_controller.text != str) {
        _controller.value = TextEditingValue(
          text: str,
          selection: TextSelection.collapsed(offset: str.length),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commitManual(String raw) {
    final parsed = int.tryParse(raw.trim());
    if (parsed == null) return;
    final clamped = parsed.clamp(1, 31);
    if (clamped != widget.selected) widget.onChanged(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Repeat on day',
          style: TextStyle(fontSize: 13, color: context.palette.muted),
        ),
        const SizedBox(height: 8),
        // 7-column calendar grid. Each day is a tappable circle button —
        // selected day uses the accent fill; days 29–31 are still tappable
        // and the recurrence calc clamps to the last day of months that
        // don't have them (e.g. day 31 → Feb 28/29).
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 1.1,
          ),
          itemCount: 31,
          itemBuilder: (_, i) {
            final day = i + 1;
            final isSelected = day == widget.selected;
            return Material(
              color: isSelected ? context.palette.accent : Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => widget.onChanged(day),
                child: Center(
                  child: Text(
                    '$day',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? cs.onPrimary : null,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        // Manual numeric entry — same model, alternative input. Useful for
        // accessibility and for users who type faster than they tap.
        Row(
          children: [
            Text(
              'Or type day',
              style: TextStyle(fontSize: 12, color: context.palette.muted),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 56,
              child: TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                  border: OutlineInputBorder(),
                ),
                onChanged: _commitManual,
                onSubmitted: _commitManual,
              ),
            ),
            const SizedBox(width: 6),
            if (widget.selected >= 29)
              Expanded(
                child: Text(
                  '(months without day ${widget.selected} use the last day)',
                  style: TextStyle(fontSize: 11, color: context.palette.muted),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
