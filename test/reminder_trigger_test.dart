import 'package:daymark/models/countdown_event.dart';
import 'package:daymark/services/reminder_service.dart';
import 'package:flutter_test/flutter_test.dart';

CountdownEvent _event({int reminderDays = 1, int reminderHour = 9}) =>
    CountdownEvent(
      id: 'e1',
      title: '纪念日',
      date: DateTime(2026, 5, 20),
      reminderDays: reminderDays,
      reminderHour: reminderHour,
    );

/// 一个远早于所有夹具的「现在」，用来验证触发时刻本身。
///
/// 必须早于最靠前的那个触发时刻（跨年用例算出来是 2025-12-31 09:00），
/// 否则会被「已经过去就不安排」这条规则挡掉，断言全线变 null。
final DateTime _early = DateTime(2025, 1, 1);

void main() {
  group('reminderTrigger', () {
    test('不提醒的记录没有触发时刻', () {
      expect(
        reminderTrigger(_event(reminderDays: -1), DateTime(2026, 5, 20), _early),
        isNull,
      );
    });

    test('当天提醒用记录自己的时刻，而不是写死的 9 点', () {
      expect(
        reminderTrigger(
          _event(reminderDays: 0, reminderHour: 21),
          DateTime(2026, 5, 20),
          _early,
        ),
        DateTime(2026, 5, 20, 21),
      );
    });

    test('提前 1 天 / 7 天 / 自定义 30 天各往前挪对应天数', () {
      DateTime? at(int days) =>
          reminderTrigger(_event(reminderDays: days), DateTime(2026, 5, 20), _early);

      expect(at(1), DateTime(2026, 5, 19, 9));
      expect(at(7), DateTime(2026, 5, 13, 9));
      expect(at(30), DateTime(2026, 4, 20, 9));
    });

    test('0 点也是合法时刻', () {
      expect(
        reminderTrigger(
          _event(reminderDays: 0, reminderHour: 0),
          DateTime(2026, 5, 20),
          _early,
        ),
        DateTime(2026, 5, 20),
      );
    });

    test('跨月往前数：3 月 1 日提前 1 天落在 2 月最后一天', () {
      expect(
        reminderTrigger(_event(reminderDays: 1), DateTime(2026, 3, 1), _early),
        DateTime(2026, 2, 28, 9),
      );
    });

    test('跨年往前数：1 月 1 日提前 1 天落在上一年最后一天', () {
      expect(
        reminderTrigger(_event(reminderDays: 1), DateTime(2026, 1, 1), _early),
        DateTime(2025, 12, 31, 9),
      );
    });

    test('闰年 2 月 29 日提前 1 天落在 2 月 28 日', () {
      expect(
        reminderTrigger(_event(reminderDays: 1), DateTime(2028, 2, 29), _early),
        DateTime(2028, 2, 28, 9),
      );
    });

    test('触发时刻已经过去就不再安排', () {
      expect(
        reminderTrigger(
          _event(reminderDays: 0),
          DateTime(2026, 5, 20),
          DateTime(2026, 5, 20, 10),
        ),
        isNull,
      );
    });

    test('正好等于现在也算过去，不排一个立刻要响的提醒', () {
      expect(
        reminderTrigger(
          _event(reminderDays: 0),
          DateTime(2026, 5, 20),
          DateTime(2026, 5, 20, 9),
        ),
        isNull,
      );
    });

    test('差一秒还没到就照常安排', () {
      expect(
        reminderTrigger(
          _event(reminderDays: 0),
          DateTime(2026, 5, 20),
          DateTime(2026, 5, 20, 8, 59, 59),
        ),
        DateTime(2026, 5, 20, 9),
      );
    });
  });

  group('notificationId', () {
    test('同一条记录的每一次发生，id 稳定不变', () {
      expect(notificationId('event-1', 0), notificationId('event-1', 0));
    });

    test('同一条记录的两次发生要错开，否则后者会顶掉前者', () {
      expect(notificationId('event-1', 0), isNot(notificationId('event-1', 1)));
    });

    test('不同记录的 id 不同', () {
      expect(notificationId('event-1', 0), isNot(notificationId('event-2', 0)));
      expect(
        notificationId('2026-birthday-a', 0),
        isNot(notificationId('2026-birthday-b', 0)),
      );
    });

    test('始终落在 Android 能接受的 32 位正整数范围内', () {
      for (final id in ['', 'a', 'e1', '很长的一条记录标识-2026-05-20', '😀']) {
        for (var index = 0; index < 3; index++) {
          final value = notificationId(id, index);
          expect(value, greaterThanOrEqualTo(0));
          expect(value, lessThanOrEqualTo(0x7fffffff));
        }
      }
    });
  });
}
