import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/models/enums.dart';
import 'package:todo_app/models/recurrence.dart';

void main() {
  group('Recurrence.daily', () {
    test('nextOccurrenceAfter returns midnight of the next day', () {
      final r = Recurrence.daily();
      final next = r.nextOccurrenceAfter(DateTime(2026, 1, 15, 14, 30));
      expect(next, DateTime(2026, 1, 16));
    });

    test('label is "Every day"', () {
      expect(Recurrence.daily().label, 'Every day');
    });

    test('round-trips through JSON', () {
      final r = Recurrence.daily();
      expect(Recurrence.fromJson(r.toJson()).frequency,
          RecurrenceFrequency.daily);
    });
  });

  group('Recurrence.weeklyDays', () {
    test('picks the next chosen weekday', () {
      // Monday Jan 12 → next Wed is Jan 14
      final r = Recurrence.weeklyDays({DateTime.wednesday, DateTime.friday});
      final next = r.nextOccurrenceAfter(DateTime(2026, 1, 12)); // Mon
      expect(next, DateTime(2026, 1, 14)); // Wed
    });

    test('wraps to next week when no weekday remains this week', () {
      // Sat Jan 17 → next Mon is Jan 19
      final r = Recurrence.weeklyDays({DateTime.monday});
      final next = r.nextOccurrenceAfter(DateTime(2026, 1, 17)); // Sat
      expect(next, DateTime(2026, 1, 19)); // Mon
    });

    test('label condenses common groupings', () {
      expect(
        Recurrence.weeklyDays(
                {1, 2, 3, 4, 5} /* Mon-Fri */).label,
        'Every weekday',
      );
      expect(
        Recurrence.weeklyDays({6, 7} /* Sat-Sun */).label,
        'Every weekend',
      );
      expect(
        Recurrence.weeklyDays(
                {DateTime.monday, DateTime.wednesday, DateTime.friday}).label,
        'Every Mon, Wed, Fri',
      );
    });

    test('round-trips through JSON', () {
      final r = Recurrence.weeklyDays({2, 4});
      final parsed = Recurrence.fromJson(r.toJson());
      expect(parsed.frequency, RecurrenceFrequency.weeklyDays);
      expect(parsed.daysOfWeek, {2, 4});
    });
  });

  group('Recurrence.everyNDays', () {
    test('adds N days exactly', () {
      final r = Recurrence.everyNDays(3);
      final next = r.nextOccurrenceAfter(DateTime(2026, 3, 1));
      expect(next, DateTime(2026, 3, 4));
    });

    test('label includes N', () {
      expect(Recurrence.everyNDays(5).label, 'Every 5 days');
    });

    test('N=1 is allowed and labelled as "Every day"', () {
      final r = Recurrence.everyNDays(1);
      expect(r.label, 'Every day');
      // And the math: nextOccurrenceAfter steps one day.
      expect(
        r.nextOccurrenceAfter(DateTime(2026, 5, 1, 14)),
        DateTime(2026, 5, 2),
      );
    });

    test('round-trips through JSON', () {
      final r = Recurrence.everyNDays(7);
      final parsed = Recurrence.fromJson(r.toJson());
      expect(parsed.frequency, RecurrenceFrequency.everyNDays);
      expect(parsed.everyNDays, 7);
    });
  });

  group('Recurrence.monthly', () {
    test('returns the target day this month when still in the future', () {
      final r = Recurrence.monthly(20);
      final next = r.nextOccurrenceAfter(DateTime(2026, 5, 5));
      expect(next, DateTime(2026, 5, 20));
    });

    test('rolls to next month when the day has passed', () {
      final r = Recurrence.monthly(5);
      final next = r.nextOccurrenceAfter(DateTime(2026, 5, 10));
      expect(next, DateTime(2026, 6, 5));
    });

    test('clamps to last day of month when target day does not exist', () {
      // Day 31 in February (non-leap) → Feb 28
      final r = Recurrence.monthly(31);
      final next = r.nextOccurrenceAfter(DateTime(2026, 2, 1));
      expect(next, DateTime(2026, 2, 28));
    });

    test('clamps to leap-day correctly', () {
      // Day 31 in February 2028 (leap) → Feb 29
      final r = Recurrence.monthly(31);
      final next = r.nextOccurrenceAfter(DateTime(2028, 2, 1));
      expect(next, DateTime(2028, 2, 29));
    });

    test('rolls across year boundary', () {
      final r = Recurrence.monthly(15);
      final next = r.nextOccurrenceAfter(DateTime(2026, 12, 20));
      expect(next, DateTime(2027, 1, 15));
    });

    test('round-trips through JSON', () {
      final r = Recurrence.monthly(15);
      final parsed = Recurrence.fromJson(r.toJson());
      expect(parsed.frequency, RecurrenceFrequency.monthly);
      expect(parsed.dayOfMonth, 15);
    });
  });

  group('Recurrence equality', () {
    test('same frequency + params compare equal', () {
      expect(Recurrence.everyNDays(3) == Recurrence.everyNDays(3), isTrue);
      expect(Recurrence.weeklyDays({1, 3}) == Recurrence.weeklyDays({3, 1}),
          isTrue);
    });

    test('different params compare unequal', () {
      expect(Recurrence.everyNDays(3) == Recurrence.everyNDays(4), isFalse);
      expect(Recurrence.daily() == Recurrence.everyNDays(2), isFalse);
    });
  });
}
