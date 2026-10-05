import 'package:flutter_test/flutter_test.dart';
import 'package:daymark/data/holiday_catalog.dart';
import 'package:daymark/models/holiday_data.dart';

void main() {
  group('HolidayCatalog', () {
    test('provides the published 2026 holiday periods', () {
      final spans = HolidayCatalog.spansForYear(2026);

      expect(spans, hasLength(7));
      expect(HolidayCatalog.holidayName(DateTime(2026, 2, 15)), '春节');
      expect(HolidayCatalog.holidayName(DateTime(2026, 2, 23)), '春节');
      expect(HolidayCatalog.holidayName(DateTime(2026, 2, 24)), isNull);
    });

    test('marks the published makeup workdays', () {
      expect(HolidayCatalog.isMakeupWorkday(DateTime(2026, 2, 14)), isTrue);
      expect(HolidayCatalog.isMakeupWorkday(DateTime(2026, 2, 15)), isFalse);
      expect(HolidayCatalog.makeupWorkdays(2026), hasLength(6));
    });

    test('does not infer arrangements for unpublished years', () {
      expect(HolidayCatalog.spansForYear(2027), isEmpty);
      expect(HolidayCatalog.makeupWorkdays(2027), isEmpty);
    });
  });

  group('HolidayCatalog.latestYear', () {
    setUp(HolidayCatalog.clearOnline);
    tearDown(HolidayCatalog.clearOnline);

    test('没有线上数据时就是内置数据年份', () {
      expect(HolidayCatalog.hasOnlineData, isFalse);
      expect(HolidayCatalog.latestYear, HolidayCatalog.publishedYear);
      expect(HolidayCatalog.latestYear, 2026);
    });

    test('线上有更新的年份时取更新的那一年', () {
      HolidayCatalog.applyOnline(
        {
          2027: HolidayData.fromJson(2027, {
            'source': '线上2027年通知',
            'sourceDate': '2026-11-04',
            'spans': [
              {'name': '元旦', 'start': '2027-01-01', 'end': '2027-01-03'},
            ],
            'makeupWorkdays': ['2027-01-10'],
          })!,
        },
        source: '线上来源',
        fetchedAt: DateTime(2026, 12, 1),
      );

      expect(HolidayCatalog.latestYear, 2027);
      expect(HolidayCatalog.hasOnlineData, isTrue);
      expect(HolidayCatalog.sourceFor(2027), '线上2027年通知');
      expect(HolidayCatalog.spansForYear(2027), hasLength(1));
      expect(HolidayCatalog.holidayName(DateTime(2027, 1, 2)), '元旦');
    });

    test('线上只剩更早的年份时最新年份不会倒退', () {
      HolidayCatalog.applyOnline(
        {
          2025: HolidayData.fromJson(2025, {
            'source': '线上2025年通知',
            'spans': [
              {'name': '元旦', 'start': '2025-01-01', 'end': '2025-01-01'},
            ],
            'makeupWorkdays': ['2025-01-26'],
          })!,
        },
        source: '线上来源',
        fetchedAt: DateTime(2026, 12, 1),
      );

      expect(
        HolidayCatalog.latestYear,
        HolidayCatalog.publishedYear,
        reason: '线上只有 2025 年，最新年份不能显示成 2025',
      );
      expect(HolidayCatalog.latestYear, 2026);
      expect(HolidayCatalog.hasOnlineData, isTrue);
      expect(HolidayCatalog.onlineSource, '线上来源');
      expect(HolidayCatalog.onlineFetchedAt, DateTime(2026, 12, 1));

      // 2026 年依旧用内置安排，2025 年才走线上覆盖。
      expect(HolidayCatalog.sourceFor(2026), HolidayCatalog.source);
      expect(HolidayCatalog.spansForYear(2026), hasLength(7));
      expect(HolidayCatalog.holidayName(DateTime(2026, 2, 15)), '春节');
      expect(HolidayCatalog.sourceFor(2025), '线上2025年通知');
      expect(HolidayCatalog.spansForYear(2025), hasLength(1));
      expect(HolidayCatalog.makeupWorkdays(2025), [DateTime(2025, 1, 26)]);
    });
  });
}
