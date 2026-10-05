import 'package:daymark/models/countdown_event.dart';
import 'package:daymark/models/day_override.dart';
import 'package:flutter_test/flutter_test.dart';

const DateTime _date = DateTime(2026, 3, 1);

/// `reminderHour` 决定提醒当天几点弹通知，用户直接看得见，而且数据来自用户自己
/// 的备份文件，所以「缺字段」和「越界值」的处理必须稳定：缺字段回落到默认的 9 点，
/// 越界值夹到 0..23，不能让一条脏备份把提醒排到非法时间。
void main() {
  group('CountdownEvent 的提醒时刻', () {
    /// 不带这个键，等价于老备份里的事件。
    Map<String, Object?> baseMap() => {
          'id': 'e1',
          'title': '示例',
          'date': '2026-03-01',
        };

    Map<String, Object?> mapWithHour(Object? hour) => {
          ...baseMap(),
          'reminderHour': hour,
        };

    test('缺字段时回落到默认的 9 点', () {
      expect(CountdownEvent.fromMap(baseMap()).reminderHour, 9);
    });

    test('键存在但为 null 时同样回落到 9 点', () {
      expect(CountdownEvent.fromMap(mapWithHour(null)).reminderHour, 9);
    });

    test('区间内的取值原样保留', () {
      for (final hour in const [0, 1, 8, 9, 20, 23]) {
        expect(
          CountdownEvent.fromMap(mapWithHour(hour)).reminderHour,
          hour,
          reason: '$hour 点应当原样保留',
        );
      }
    });

    test('超过 23 点夹到 23 点，负数夹到 0 点', () {
      expect(CountdownEvent.fromMap(mapWithHour(24)).reminderHour, 23);
      expect(CountdownEvent.fromMap(mapWithHour(99)).reminderHour, 23);
      expect(CountdownEvent.fromMap(mapWithHour(-1)).reminderHour, 0);
      expect(CountdownEvent.fromMap(mapWithHour(-100)).reminderHour, 0);
    });

    test('备份里的浮点数被截断为整点后再夹取', () {
      expect(CountdownEvent.fromMap(mapWithHour(7.9)).reminderHour, 7);
      expect(CountdownEvent.fromMap(mapWithHour(24.5)).reminderHour, 23);
    });

    test('toMap 写出提醒时刻，copyWith 可改且不动原对象', () {
      const event = CountdownEvent(
        id: 'e1',
        title: '示例',
        date: _date,
        reminderHour: 21,
      );
      expect(event.toMap()['reminderHour'], 21);

      final changed = event.copyWith(reminderHour: 6);
      expect(changed.reminderHour, 6);
      expect(event.reminderHour, 21, reason: 'copyWith 不能就地改原对象');
    });
  });

  group('DayOverride 的提醒时刻', () {
    /// 不带这个键，等价于老备份里的改动记录。
    Map<String, Object?> baseMap() => {
          'origin': 'holiday:春节:2026-02-15',
          'title': '春节',
          'date': '2026-02-15T00:00:00.000',
          'reminderDays': -1,
        };

    Map<String, Object?> mapWithHour(Object? hour) => {
          ...baseMap(),
          'reminderHour': hour,
        };

    test('缺字段时回落到默认的 9 点', () {
      expect(DayOverride.fromMap(baseMap()).reminderHour, 9);
    });

    test('键存在但为 null 时同样回落到 9 点', () {
      expect(DayOverride.fromMap(mapWithHour(null)).reminderHour, 9);
    });

    test('区间内的取值原样保留', () {
      for (final hour in const [0, 9, 18, 23]) {
        expect(DayOverride.fromMap(mapWithHour(hour)).reminderHour, hour);
      }
    });

    test('超出范围的取值夹到边界', () {
      expect(DayOverride.fromMap(mapWithHour(30)).reminderHour, 23);
      expect(DayOverride.fromMap(mapWithHour(-5)).reminderHour, 0);
    });

    test('toMap 写出提醒时刻，copyWith 可改且不动原对象', () {
      const override = DayOverride(
        origin: 'holiday:春节:2026-02-15',
        title: '春节',
        date: _date,
        category: '重要日',
        note: '',
        reminderDays: -1,
        reminderHour: 8,
      );
      expect(override.toMap()['reminderHour'], 8);

      final changed = override.copyWith(reminderHour: 22);
      expect(changed.reminderHour, 22);
      expect(override.reminderHour, 8, reason: 'copyWith 不能就地改原对象');
    });
  });
}
