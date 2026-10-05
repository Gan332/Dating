import '../models/holiday_data.dart';

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

  // ------------------------------------------------- 线上数据覆盖层

  /// 联网更新拿到的年度数据；某一年在内置数据之外就以它为准。
  static final Map<int, HolidayData> _online = <int, HolidayData>{};

  static String _onlineSource = '';

  static DateTime? _onlineFetchedAt;

  /// 当前用到的最新年份（线上有更新年份时优先用它）。
  static int get latestYear {
    if (_online.isEmpty) return publishedYear;
    return _online.keys.reduce((a, b) => a > b ? a : b);
  }

  static String get onlineSource => _onlineSource;

  static DateTime? get onlineFetchedAt => _onlineFetchedAt;

  static bool get hasOnlineData => _online.isNotEmpty;

  /// 套用线上数据。内置数据始终保留，线上没有的年份照旧用内置的。
  static void applyOnline(
    Map<int, HolidayData> years, {
    String source = '',
    DateTime? fetchedAt,
  }) {
    _online
      ..clear()
      ..addAll(years);
    _onlineSource = source;
    _onlineFetchedAt = fetchedAt;
  }

  /// 放弃线上数据，回到内置安排。
  static void clearOnline() {
    _online.clear();
    _onlineSource = '';
    _onlineFetchedAt = null;
  }

  /// 某一年放假安排的来源说明。
  static String sourceFor(int year) {
    final online = _online[year];
    if (online != null) {
      final source = online.source;
      return source.isEmpty ? '在线数据' : source;
    }
    return source;
  }

  static List<HolidaySpan> spansForYear(int year) {
    final online = _online[year];
    if (online != null) return List.unmodifiable(online.spans);
    return year == publishedYear ? List.unmodifiable(_spans) : const [];
  }

  static String? holidayName(DateTime date) {
    for (final span in spansForYear(date.year)) {
      if (!date.isBefore(span.start) && !date.isAfter(span.end)) {
        return span.name;
      }
    }
    return null;
  }

  static bool isMakeupWorkday(DateTime date) {
    final online = _online[date.year];
    if (online != null) {
      return online.makeupWorkdays.any((day) => _key(day) == _key(date));
    }
    return _makeupWorkdays.contains(_key(date));
  }

  // 用块函数体避免级联运算符 `..` 出现在条件表达式里——`? a..b() : c` 不是合法的
  // Dart 语法，会让 kernel 编译直接失败。
  static List<DateTime> makeupWorkdays(int year) {
    final online = _online[year];
    if (online != null) {
      final days = List.of(online.makeupWorkdays)..sort();
      return List.unmodifiable(days);
    }
    if (year != publishedYear) return const [];
    final days = _makeupWorkdays.map(DateTime.parse).toList()..sort();
    return List.unmodifiable(days);
  }

  static String _key(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
