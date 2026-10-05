import '../data/holiday_catalog.dart';

/// 某一年的放假安排（可能来自线上更新，也可能是内置数据解析而来）。
class HolidayData {
  const HolidayData({
    required this.year,
    required this.source,
    required this.sourceDate,
    required this.spans,
    required this.makeupWorkdays,
  });

  final int year;

  /// 官方来源说明。
  final String source;

  /// 官方发布日期，yyyy-MM-dd；公共接口可能没有。
  final String sourceDate;

  /// 连续的放假区间。
  final List<HolidaySpan> spans;

  /// 需要上班的补休日。
  final List<DateTime> makeupWorkdays;

  static DateTime? _parseDay(String? raw) {
    if (raw == null) return null;
    final value = DateTime.tryParse(raw.trim());
    if (value == null) return null;
    return DateTime(value.year, value.month, value.day);
  }

  /// 解析本应用的数据格式（assets/holidays/holidays.json）。
  static HolidayData? fromJson(int year, Map<String, dynamic> json) {
    final rawSpans = json['spans'];
    if (rawSpans is! List) return null;
    final spans = <HolidaySpan>[];
    for (final raw in rawSpans) {
      if (raw is! Map<String, dynamic>) continue;
      final name = (raw['name'] as String?)?.trim() ?? '';
      final start = _parseDay(raw['start'] as String?);
      final end = _parseDay(raw['end'] as String?) ?? start;
      if (name.isEmpty || start == null || end == null || end.isBefore(start)) {
        continue;
      }
      spans.add(HolidaySpan(name, start, end));
    }
    if (spans.isEmpty) return null;

    final workdays = <DateTime>[];
    final rawWorkdays = json['makeupWorkdays'];
    if (rawWorkdays is List) {
      for (final raw in rawWorkdays) {
        final day = _parseDay(raw as String?);
        if (day != null) workdays.add(day);
      }
    }

    return HolidayData(
      year: year,
      source: (json['source'] as String?) ?? '',
      sourceDate: (json['sourceDate'] as String?) ?? '',
      spans: spans,
      makeupWorkdays: workdays,
    );
  }

  /// 解析公共接口 Timor 的格式：把连续的假期合并成区间，补休日单独收集。
  static HolidayData? fromTimor(int year, Map<String, dynamic> json) {
    final days = json['holiday'];
    if (days is! Map<String, dynamic>) return null;
    final entries = <(DateTime, String, bool)>[];
    for (final raw in days.values) {
      if (raw is! Map<String, dynamic>) continue;
      final day = _parseDay(raw['date'] as String?);
      if (day == null) continue;
      entries.add((day, (raw['name'] as String?)?.trim() ?? '', raw['holiday'] == true));
    }
    if (entries.isEmpty) return null;
    entries.sort((a, b) => a.$1.compareTo(b.$1));

    final spans = <HolidaySpan>[];
    final workdays = <DateTime>[];
    for (final entry in entries) {
      if (!entry.$3) {
        workdays.add(entry.$1);
        continue;
      }
      final name = entry.$2;
      if (name.isEmpty) continue;
      final previous = spans.isEmpty ? null : spans.last;
      if (previous != null &&
          previous.name == name &&
          _isNextDay(previous.end, entry.$1)) {
        spans[spans.length - 1] = HolidaySpan(name, previous.start, entry.$1);
      } else {
        spans.add(HolidaySpan(name, entry.$1, entry.$1));
      }
    }
    if (spans.isEmpty) return null;

    return HolidayData(
      year: year,
      source: 'Timor 节假日接口',
      sourceDate: '',
      spans: spans,
      makeupWorkdays: workdays,
    );
  }

  static bool _isNextDay(DateTime from, DateTime to) =>
      to.year == from.year && to.month == from.month && to.day == from.day + 1;
}

/// 一次更新拿到的若干年度数据。
class HolidaySnapshot {
  const HolidaySnapshot({
    required this.years,
    required this.source,
    required this.fetchedAt,
  });

  final Map<int, HolidayData> years;
  final String source;
  final DateTime fetchedAt;

  Map<String, Object?> toJson() => {
        'format': 'daymark.holidays',
        'version': 1,
        'source': source,
        'fetchedAt': fetchedAt.toIso8601String(),
        'years': {
          for (final entry in years.entries)
            entry.key.toString(): {
              'source': entry.value.source,
              'sourceDate': entry.value.sourceDate,
              'spans': [
                for (final span in entry.value.spans)
                  {
                    'name': span.name,
                    'start': _iso(span.start),
                    'end': _iso(span.end),
                  },
              ],
              'makeupWorkdays': [
                for (final day in entry.value.makeupWorkdays) _iso(day),
              ],
            },
        },
      };

  /// 解析缓存或线上数据；任何一年都认不出来就返回 null。
  static HolidaySnapshot? fromJson(Map<String, dynamic> json) {
    if (json['format'] != 'daymark.holidays') return null;
    final years = json['years'];
    if (years is! Map<String, dynamic>) return null;
    final parsed = <int, HolidayData>{};
    for (final entry in years.entries) {
      final year = int.tryParse(entry.key);
      final value = entry.value;
      if (year == null || value is! Map<String, dynamic>) continue;
      final data = HolidayData.fromJson(year, value);
      if (data != null) parsed[year] = data;
    }
    if (parsed.isEmpty) return null;
    return HolidaySnapshot(
      years: parsed,
      source: (json['source'] as String?) ?? '在线数据',
      fetchedAt:
          DateTime.tryParse((json['fetchedAt'] as String?) ?? '') ?? DateTime.now(),
    );
  }

  static String _iso(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}
