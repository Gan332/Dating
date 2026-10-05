import 'dart:convert';

import 'package:daymark/data/holiday_catalog.dart';
import 'package:daymark/models/holiday_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(HolidayCatalog.clearOnline);

  group('自建数据格式', () {
    test('解析年度放假区间与补休日', () {
      final data = HolidayData.fromJson(2026, {
        'source': '测试来源',
        'sourceDate': '2025-11-04',
        'spans': [
          {'name': '春节', 'start': '2026-02-15', 'end': '2026-02-23'},
        ],
        'makeupWorkdays': ['2026-02-14', '2026-02-28'],
      });

      expect(data, isNotNull);
      expect(data!.spans.single.name, '春节');
      expect(data.makeupWorkdays, hasLength(2));
    });

    test('缺字段或格式不对时返回 null', () {
      expect(HolidayData.fromJson(2026, const {}), isNull);
      expect(
        HolidayData.fromJson(2026, {
          'spans': '不是数组',
        }),
        isNull,
      );
      expect(
        HolidayData.fromJson(2026, {
          'spans': [
            {'name': '', 'start': '2026-01-01', 'end': '2026-01-02'},
          ],
        }),
        isNull,
      );
    });

    test('快照可以原样存取', () {
      final data = HolidayData.fromJson(2026, {
        'source': '测试来源',
        'spans': [
          {'name': '国庆节', 'start': '2026-10-01', 'end': '2026-10-07'},
        ],
        'makeupWorkdays': ['2026-10-10'],
      })!;
      final snapshot = HolidaySnapshot(
        years: {2026: data},
        source: '测试来源',
        fetchedAt: DateTime(2026, 1, 2, 3, 4),
      );

      final restored = HolidaySnapshot.fromJson(
        jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, dynamic>,
      );

      expect(restored, isNotNull);
      expect(restored!.years[2026]!.spans.single.name, '国庆节');
      expect(restored.source, '测试来源');
      expect(restored.fetchedAt, DateTime(2026, 1, 2, 3, 4));
    });
  });

  group('公共接口格式', () {
    test('连续假期合并成区间，补休日单独收集', () {
      final data = HolidayData.fromTimor(2026, {
        'holiday': {
          '01-01': {
            'date': '2026-01-01',
            'holiday': true,
            'name': '元旦',
          },
          '01-02': {
            'date': '2026-01-02',
            'holiday': true,
            'name': '元旦',
          },
          '01-03': {
            'date': '2026-01-03',
            'holiday': true,
            'name': '元旦',
          },
          '01-04': {
            'date': '2026-01-04',
            'holiday': false,
            'name': '班',
          },
          '02-17': {
            'date': '2026-02-17',
            'holiday': true,
            'name': '春节',
          },
        },
      });

      expect(data, isNotNull);
      expect(data!.spans, hasLength(2));
      expect(data.spans.first.name, '元旦');
      expect(data.spans.first.start, DateTime(2026, 1, 1));
      expect(data.spans.first.end, DateTime(2026, 1, 3));
      expect(data.spans.last.name, '春节');
      expect(data.makeupWorkdays, [DateTime(2026, 1, 4)]);
    });

    test('结构不认识时返回 null', () {
      expect(HolidayData.fromTimor(2026, const {}), isNull);
      expect(HolidayData.fromTimor(2026, {
        'holiday': 'x',
      }), isNull);
    });
  });

  group('覆盖内置数据', () {
    test('套用线上数据后优先使用它', () {
      HolidayCatalog.applyOnline(
        {
          2026: HolidayData.fromJson(2026, {
            'source': '线上',
            'spans': [
              {'name': '元旦', 'start': '2026-01-01', 'end': '2026-01-02'},
            ],
            'makeupWorkdays': ['2026-01-03'],
          })!,
          2027: HolidayData.fromJson(2027, {
            'source': '线上',
            'spans': [
              {'name': '元旦', 'start': '2027-01-01', 'end': '2027-01-03'},
            ],
          })!,
        },
        source: '线上来源',
        fetchedAt: DateTime(2026, 1, 1),
      );

      expect(HolidayCatalog.latestYear, 2027);
      expect(HolidayCatalog.onlineSource, '线上来源');
      expect(HolidayCatalog.sourceFor(2026), '线上');
      expect(
        HolidayCatalog.holidayName(DateTime(2026, 1, 3)),
        isNull,
        reason: '线上只放到 1 月 2 日',
      );
      expect(HolidayCatalog.isMakeupWorkday(DateTime(2026, 1, 3)), isTrue);
      expect(HolidayCatalog.makeupWorkdays(2026), [DateTime(2026, 1, 3)]);
    });

    test('清除后回到内置安排', () {
      HolidayCatalog.applyOnline(
        {
          2026: HolidayData.fromJson(2026, {
            'spans': [
              {'name': '元旦', 'start': '2026-01-01', 'end': '2026-01-02'},
            ],
          })!,
        },
        source: '线上来源',
      );
      expect(HolidayCatalog.holidayName(DateTime(2026, 1, 3)), isNull);

      HolidayCatalog.clearOnline();

      expect(HolidayCatalog.hasOnlineData, isFalse);
      expect(HolidayCatalog.latestYear, HolidayCatalog.publishedYear);
      expect(HolidayCatalog.holidayName(DateTime(2026, 1, 3)), '元旦');
      expect(HolidayCatalog.isMakeupWorkday(DateTime(2026, 1, 4)), isTrue);
    });
  });
}
