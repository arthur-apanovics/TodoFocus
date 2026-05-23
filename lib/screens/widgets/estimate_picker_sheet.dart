import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_palette.dart';
import 'app_bottom_sheet.dart';

/// Bottom sheet for picking a time estimate (in minutes) for a subtask.
/// Presents common presets as chips with a "Custom…" tail option that
/// reveals a numeric input.
///
/// Result semantics:
///   • [EstimateResult.set]     — user picked a non-zero value (minutes).
///   • [EstimateResult.cleared] — user removed the existing estimate.
///   • `null` from `show()`     — user dismissed without committing.
class EstimatePickerSheet extends StatefulWidget {
  final int? initial;

  const EstimatePickerSheet({super.key, this.initial});

  static Future<EstimateResult?> show(
    BuildContext context, {
    int? initial,
  }) {
    return showModalBottomSheet<EstimateResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => EstimatePickerSheet(initial: initial),
    );
  }

  @override
  State<EstimatePickerSheet> createState() => _EstimatePickerSheetState();
}

class EstimateResult {
  final int? minutes;
  final bool cleared;

  const EstimateResult.set(int m)
      : minutes = m,
        cleared = false;
  const EstimateResult.cleared()
      : minutes = null,
        cleared = true;
}

class _EstimatePickerSheetState extends State<EstimatePickerSheet> {
  // Compact set chosen to span planning-relevant ranges without overwhelming.
  // Anything outside falls into "Custom".
  static const _presets = [5, 10, 15, 30, 45, 60, 90, 120];

  int? _selectedPreset;
  bool _custom = false;
  late int _customValue;
  late final TextEditingController _customController;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null && _presets.contains(init)) {
      _selectedPreset = init;
      _customValue = init;
    } else if (init != null && init > 0) {
      _custom = true;
      _customValue = init;
    } else {
      _selectedPreset = 30;
      _customValue = 30;
    }
    _customController = TextEditingController(text: _customValue.toString());
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  int get _resolved {
    if (_custom) return _customValue;
    return _selectedPreset ?? 30;
  }

  String _label(int minutes) {
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final rem = minutes % 60;
    if (rem == 0) return hours == 1 ? '1 hour' : '$hours hours';
    return '${hours}h ${rem}m';
  }

  @override
  Widget build(BuildContext context) {
    final hasInitial = widget.initial != null;
    final resolved = _resolved;

    return AppBottomSheet(
      title: 'Time estimate',
      children: [
        Text(
          'How long will this step take? Pick a quick value or enter your own.',
          style: TextStyle(color: context.palette.muted, fontSize: 13),
        ),
        const SizedBox(height: 16),

        // Preset chips.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in _presets)
              ChoiceChip(
                label: Text(_label(p)),
                selected: !_custom && _selectedPreset == p,
                showCheckmark: false,
                onSelected: (_) => setState(() {
                  _custom = false;
                  _selectedPreset = p;
                }),
              ),
            ChoiceChip(
              label: const Text('Custom'),
              selected: _custom,
              showCheckmark: false,
              onSelected: (_) => setState(() {
                _custom = true;
                _selectedPreset = null;
              }),
            ),
          ],
        ),

        if (_custom) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 88,
                child: TextField(
                  controller: _customController,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(vertical: 10, horizontal: 8),
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
              const SizedBox(width: 12),
              Text('minutes',
                  style: TextStyle(color: context.palette.muted)),
            ],
          ),
        ],

        const SizedBox(height: 16),

        // Resolved preview — same affordance pattern as auto_sleep_picker_sheet.
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.palette.successSurface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.schedule,
                  color: context.palette.accent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Estimated ${_label(resolved)}',
                  style: TextStyle(
                      fontSize: 13, color: context.palette.strong),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        Row(
          children: [
            if (hasInitial)
              TextButton.icon(
                onPressed: () => Navigator.of(context)
                    .pop(const EstimateResult.cleared()),
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
              onPressed: resolved <= 0
                  ? null
                  : () => Navigator.of(context)
                      .pop(EstimateResult.set(resolved)),
              child: const Text('Apply'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Formats a minute count as a compact label suitable for inline display.
///   • <60 min → "30 min"
///   • whole hours → "2 hours"
///   • otherwise → "1h 30m"
String formatEstimate(int minutes) {
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final rem = minutes % 60;
  if (rem == 0) return hours == 1 ? '1 hour' : '$hours hours';
  return '${hours}h ${rem}m';
}
