import 'package:lunar/lunar.dart';

import '../models/countdown_event.dart';
import 'rust_date_core.dart';

class EventOccurrence {
  const EventOccurrence({
    required this.title,
    required this.date,
    required this.daysRemaining,
    this.event,
    this.subtitle = '',
    this.origin,
    this.overridden = false,
    this.reminderDays = -1,
  });

  final String title;
  final DateTime date;
  final int daysRemaining;
  final CountdownEvent? event;
  final String subtitle;

  /// 内置条目的稳定标识；为空表示这条来自用户自己的记录。
  final String? origin;

  /// 用户是否改动过这条内置条目。
  final bool overridden;

  /// -1 表示不提醒。
  final int reminderDays;

  /// 是否可以改动：自己的记录，或内置条目。
  bool get editable => event != null || origin != null;
}

class CalendarEngine {
  /// 官方节假日区间的稳定标识。区间内某一天都指回同一个内置条目。
  static String holidayOrigin(String name, DateTime start) =>
      'holiday:$name:${CountdownEvent.dateKey(start)}';

  /// 传统节日的稳定标识。
  static String festivalOrigin(DateTime date, String name) =>
      'festival:${CountdownEvent.dateKey(date)}:$name';

  static DateTime dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static int daysBetween(DateTime from, DateTime to) =>
      RustDateCore.daysBetween(dateOnly(from), dateOnly(to));

  static DateTime? lunarDate(int year, int month, int day) {
    try {
      final solar = Lunar.fromYmd(year, month, day).getSolar();
      return DateTime(solar.getYear(), solar.getMonth(), solar.getDay());
    } on Object {
      if (day != 30) return null;
      try {
        final solar = Lunar.fromYmd(year, month, 29).getSolar();
        return DateTime(solar.getYear(), solar.getMonth(), solar.getDay());
      } on Object {
        return null;
      }
    }
  }

  static List<DateTime> occurrences(
    CountdownEvent event,
    DateTime from, {
    int limit = 2,
  }) {
    final start = dateOnly(from);
    if (event.recurrence == EventRecurrence.once) {
      return [dateOnly(event.date)];
    }

    final candidates = <DateTime>{};
    if (event.recurrence == EventRecurrence.solarYearly) {
      for (var year = start.year; year <= start.year + 3; year++) {
        final day = event.date.day > DateTime(year, event.date.month + 1, 0).day
            ? DateTime(year, event.date.month + 1, 0).day
            : event.date.day;
        final date = DateTime(year, event.date.month, day);
        if (!date.isBefore(start)) candidates.add(date);
      }
    } else {
      final month = event.lunarMonth ?? Lunar.fromDate(event.date).getMonth();
      final day = event.lunarDay ?? Lunar.fromDate(event.date).getDay();
      for (var year = start.year - 1; year <= start.year + 3; year++) {
        final date = lunarDate(year, month, day);
        if (date != null && !date.isBefore(start)) candidates.add(date);
      }
    }

    final ordered = candidates.toList()..sort();
    return ordered.take(limit).toList(growable: false);
  }

  static EventOccurrence? nextOccurrence(
    CountdownEvent event,
    DateTime now,
  ) {
    final today = dateOnly(now);
    final dates = occurrences(event, today, limit: 1);
    if (dates.isEmpty) return null;
    final date = dates.first;
    return EventOccurrence(
      title: event.title,
      date: date,
      daysRemaining: daysBetween(today, date),
      event: event,
      subtitle: event.category,
      reminderDays: event.reminderDays,
    );
  }

  static List<String> lunarFestivals(DateTime date) {
    final lunar = Lunar.fromDate(dateOnly(date));
    return [...lunar.getFestivals(), ...lunar.getOtherFestivals()];
  }

  static String lunarDayLabel(DateTime date) {
    final lunar = Lunar.fromDate(dateOnly(date));
    if (lunar.getDay() == 1) return lunar.getMonthInChinese();
    return lunar.getDayInChinese();
  }

  static String solarTerm(DateTime date) {
    final lunar = Lunar.fromDate(dateOnly(date));
    final jie = lunar.getJie();
    return jie.isNotEmpty ? jie : lunar.getQi();
  }
}
