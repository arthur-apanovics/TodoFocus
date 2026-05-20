import 'enums.dart';

/// Specification for how a [Goal] repeats over time.
///
/// A [Recurrence] is an *immutable value object* — never mutated after
/// construction. Use the named factories ([Recurrence.daily],
/// [Recurrence.weeklyDays], [Recurrence.everyNDays], [Recurrence.monthly])
/// rather than the private constructor; each one validates its inputs and
/// asserts the right combination of fields is set.
///
/// ## Computing the next occurrence
///
/// [nextOccurrenceAfter] returns the next [DateTime] strictly later than
/// the given moment. The returned value is at midnight (00:00 local) of
/// the target day — the [SchedulingService] applies the configured daily
/// reset time on top of that so all recurring goals trigger at the same
/// "morning" hour.
///
/// ## Serialisation
///
/// Persisted as a compact JSON map keyed by frequency name plus the
/// relevant parameter(s). Unknown payloads round-trip safely to a daily
/// recurrence to avoid crashes on schema mismatches.
class Recurrence {
  final RecurrenceFrequency frequency;

  /// Used by [RecurrenceFrequency.everyNDays]. ≥ 1. N=1 is functionally
  /// identical to [RecurrenceFrequency.daily] — both factories are kept so
  /// that legacy persisted "daily" data round-trips cleanly, but the picker
  /// now prefers `Recurrence.everyNDays(1)` as the canonical daily form.
  final int? everyNDays;

  /// Used by [RecurrenceFrequency.weeklyDays]. Non-empty subset of 1–7
  /// where 1 = Monday and 7 = Sunday (matches Dart's [DateTime.weekday]).
  final Set<int>? daysOfWeek;

  /// Used by [RecurrenceFrequency.monthly]. 1–31; clamps to the last day
  /// of any given month when the chosen day doesn't exist.
  final int? dayOfMonth;

  const Recurrence._({
    required this.frequency,
    this.everyNDays,
    this.daysOfWeek,
    this.dayOfMonth,
  });

  // ── Factories ─────────────────────────────────────────────────────────────

  factory Recurrence.daily() =>
      const Recurrence._(frequency: RecurrenceFrequency.daily);

  factory Recurrence.weeklyDays(Set<int> daysOfWeek) {
    assert(daysOfWeek.isNotEmpty, 'Pick at least one weekday');
    assert(daysOfWeek.every((d) => d >= 1 && d <= 7),
        'Weekdays must be in 1..7 (Mon..Sun)');
    return Recurrence._(
      frequency: RecurrenceFrequency.weeklyDays,
      daysOfWeek: Set.unmodifiable(daysOfWeek),
    );
  }

  factory Recurrence.everyNDays(int n) {
    assert(n >= 1, 'everyNDays needs n ≥ 1');
    return Recurrence._(
      frequency: RecurrenceFrequency.everyNDays,
      everyNDays: n,
    );
  }

  factory Recurrence.monthly(int dayOfMonth) {
    assert(dayOfMonth >= 1 && dayOfMonth <= 31,
        'dayOfMonth must be in 1..31');
    return Recurrence._(
      frequency: RecurrenceFrequency.monthly,
      dayOfMonth: dayOfMonth,
    );
  }

  // ── Scheduling math ───────────────────────────────────────────────────────

  /// Returns the next occurrence strictly *after* [after], at midnight of
  /// the target day. Callers add a time-of-day offset (e.g. the daily
  /// reset hour) on top of this.
  DateTime nextOccurrenceAfter(DateTime after) {
    final base = DateTime(after.year, after.month, after.day);
    switch (frequency) {
      case RecurrenceFrequency.daily:
        return base.add(const Duration(days: 1));

      case RecurrenceFrequency.weeklyDays:
        // Walk forward day-by-day up to 7 steps to find the next chosen day.
        for (var i = 1; i <= 7; i++) {
          final candidate = base.add(Duration(days: i));
          if (daysOfWeek!.contains(candidate.weekday)) return candidate;
        }
        // Unreachable given the non-empty invariant, but defensive fallback.
        return base.add(const Duration(days: 1));

      case RecurrenceFrequency.everyNDays:
        return base.add(Duration(days: everyNDays!));

      case RecurrenceFrequency.monthly:
        return _nextMonthlyAfter(after);
    }
  }

  /// Walks month-by-month until we find the first month where the clamped
  /// day-of-month yields a date strictly later than [after]. Clamping
  /// means "day 31 in February" snaps to Feb 28 (or 29 in leap years).
  DateTime _nextMonthlyAfter(DateTime after) {
    var year = after.year;
    var month = after.month;
    // Try the current month first; if the clamped day is ≤ after's date,
    // roll into the next month.
    while (true) {
      // DateTime(year, month + 1, 0) gives the last day of `month`.
      final lastDay = DateTime(year, month + 1, 0).day;
      final day = dayOfMonth! > lastDay ? lastDay : dayOfMonth!;
      final candidate = DateTime(year, month, day);
      if (candidate.isAfter(after)) return candidate;
      month++;
      if (month > 12) {
        month = 1;
        year++;
      }
    }
  }

  // ── Human-readable label ──────────────────────────────────────────────────

  /// Compact label for chips and pickers, e.g. "Every Mon, Wed, Fri".
  String get label {
    switch (frequency) {
      case RecurrenceFrequency.daily:
        return 'Every day';
      case RecurrenceFrequency.weeklyDays:
        const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        final sorted = daysOfWeek!.toList()..sort();
        // Detect common groupings for nicer copy.
        if (sorted.length == 7) return 'Every day';
        if (sorted.length == 5 &&
            sorted.every((d) => d >= 1 && d <= 5)) {
          return 'Every weekday';
        }
        if (sorted.length == 2 && sorted.contains(6) && sorted.contains(7)) {
          return 'Every weekend';
        }
        return 'Every ${sorted.map((d) => names[d - 1]).join(', ')}';
      case RecurrenceFrequency.everyNDays:
        // N=1 reads more naturally as "Every day"; otherwise "Every N days".
        if (everyNDays == 1) return 'Every day';
        return 'Every $everyNDays days';
      case RecurrenceFrequency.monthly:
        return 'Monthly on day $dayOfMonth';
    }
  }

  // ── Serialisation ─────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'frequency': frequency.name,
        if (everyNDays != null) 'everyNDays': everyNDays,
        if (daysOfWeek != null) 'daysOfWeek': daysOfWeek!.toList(),
        if (dayOfMonth != null) 'dayOfMonth': dayOfMonth,
      };

  factory Recurrence.fromJson(Map<String, dynamic> json) {
    final freq = RecurrenceFrequency.values
        .asNameMap()[json['frequency'] as String? ?? ''] ??
        RecurrenceFrequency.daily;
    switch (freq) {
      case RecurrenceFrequency.daily:
        return Recurrence.daily();
      case RecurrenceFrequency.weeklyDays:
        final raw = (json['daysOfWeek'] as List?)?.cast<int>() ?? [];
        if (raw.isEmpty) return Recurrence.daily(); // safe fallback
        return Recurrence.weeklyDays(raw.toSet());
      case RecurrenceFrequency.everyNDays:
        final n = (json['everyNDays'] as int?) ?? 1;
        return Recurrence.everyNDays(n < 1 ? 1 : n);
      case RecurrenceFrequency.monthly:
        final d = (json['dayOfMonth'] as int?) ?? 1;
        return Recurrence.monthly(d.clamp(1, 31));
    }
  }

  // ── Equality ──────────────────────────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (other is! Recurrence) return false;
    if (other.frequency != frequency) return false;
    if (other.everyNDays != everyNDays) return false;
    if (other.dayOfMonth != dayOfMonth) return false;
    final a = daysOfWeek;
    final b = other.daysOfWeek;
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return a.length == b.length && a.every(b.contains);
  }

  @override
  int get hashCode => Object.hash(
        frequency,
        everyNDays,
        dayOfMonth,
        daysOfWeek == null
            ? null
            : Object.hashAllUnordered(daysOfWeek!),
      );
}
