class HolidaySpan {
  const HolidaySpan(this.name, this.start, this.end);

  final String name;
  final DateTime start;
  final DateTime end;
}

class HolidayCatalog {
  static const int publishedYear = 2026;
  static const String source =
      '国务院办公厅《国务院办公厅关于2026年部分节假日安排的通知》国办发明电〔2025〕7号';
  static const String sourceDate = '2025-11-04';

  static final List<HolidaySpan> _spans = [
    HolidaySpan('元旦', DateTime(2026, 1, 1), DateTime(2026, 1, 3)),
    HolidaySpan('春节', DateTime(2026, 2, 15), DateTime(2026, 2, 23)),
    HolidaySpan('清明节', DateTime(2026, 4, 4), DateTime(2026, 4, 6)),
    HolidaySpan('劳动节', DateTime(2026, 5, 1), DateTime(2026, 5, 5)),
    HolidaySpan('端午节', DateTime(2026, 6, 19), DateTime(2026, 6, 21)),
    HolidaySpan('中秋节', DateTime(2026, 9, 25), DateTime(2026, 9, 27)),
    HolidaySpan('国庆节', DateTime(2026, 10, 1), DateTime(2026, 10, 7)),
  ];

  static final Set<String> _makeupWorkdays = {
    '2026-01-04',
    '2026-02-14',
    '2026-02-28',
    '2026-05-09',
    '2026-09-20',
    '2026-10-10',
  };

  static List<HolidaySpan> spansForYear(int year) =>
      year == publishedYear ? List.unmodifiable(_spans) : const [];

  static String? holidayName(DateTime date) {
    for (final span in spansForYear(date.year)) {
      if (!date.isBefore(span.start) && !date.isAfter(span.end)) {
        return span.name;
      }
    }
    return null;
  }

  static bool isMakeupWorkday(DateTime date) =>
      _makeupWorkdays.contains(_key(date));

  static List<DateTime> makeupWorkdays(int year) =>
      year == publishedYear
          ? _makeupWorkdays.map(DateTime.parse).toList()..sort()
          : const [];

  static String _key(DateTime date) =>
      date.year.toString().padLeft(4, '0') +
      '-' +
      date.month.toString().padLeft(2, '0') +
      '-' +
      date.day.toString().padLeft(2, '0');
}
