import 'package:flutter_test/flutter_test.dart';
import 'package:daymark/core/calendar_engine.dart';
import 'package:daymark/models/countdown_event.dart';

void main() {
  group('CalendarEngine.daysBetween', () {
    test('counts leap day and preserves direction', () {
      expect(
        CalendarEngine.daysBetween(DateTime(2024, 2, 28), DateTime(2024, 3, 1)),
        2,
      );
      expect(
        CalendarEngine.daysBetween(DateTime(2024, 3, 1), DateTime(2024, 2, 28)),
        -2,
      );
    });
  });

  group('CalendarEngine.occurrences', () {
    test('keeps past one-time dates available for history lists', () {
      final event = CountdownEvent(
        id: 'past-event',
        title: '已经过去的日子',
        date: DateTime(2026, 10, 1),
      );

      final occurrence =
          CalendarEngine.nextOccurrence(event, DateTime(2026, 10, 5));

      expect(occurrence, isNotNull);
      final resolved = occurrence!;
      expect(resolved.date, DateTime(2026, 10, 1));
      expect(resolved.daysRemaining, -4);
    });

    test('clamps a February 29 solar anniversary in non-leap years', () {
      final event = CountdownEvent(
        id: 'leap-day',
        title: '闰日纪念',
        date: DateTime(2024, 2, 29),
        recurrence: EventRecurrence.solarYearly,
      );

      expect(
        CalendarEngine.occurrences(event, DateTime(2025, 1, 1), limit: 2),
        [DateTime(2025, 2, 28), DateTime(2026, 2, 28)],
      );
    });

    test('returns the next lunar new year occurrence on or after the start', () {
      final event = CountdownEvent(
        id: 'lunar-new-year',
        title: '春节',
        date: CalendarEngine.lunarDate(2024, 1, 1)!,
        recurrence: EventRecurrence.lunarYearly,
        lunarMonth: 1,
        lunarDay: 1,
      );
      final expected = CalendarEngine.lunarDate(2025, 1, 1)!;

      expect(
        CalendarEngine.occurrences(event, expected, limit: 2),
        [expected, CalendarEngine.lunarDate(2026, 1, 1)!],
      );
    });
  });
}
