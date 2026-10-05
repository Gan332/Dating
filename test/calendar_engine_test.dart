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

  group('CalendarEngine.lunarFestivalsInRange', () {
    // 下面用到的农历日期都对照同一份农历表逐天核过：
    //   2025 年春节（正月初一）= 2025-01-29，前一晚除夕 = 2025-01-28；
    //   2025 年端午节（五月初五）= 2025-05-31。
    // 春节紧贴除夕、端午又落在长窗口的末位，两头正好能卡住边界。
    test('包含起始当天，不包含 from + days 当天', () {
      // [2025-01-29, +1) 只有春节本身，没有前一晚的除夕。
      expect(
        CalendarEngine.lunarFestivalsInRange(DateTime(2025, 1, 29), 1),
        {DateTime(2025, 1, 29): ['春节']},
      );

      // 窗口从除夕当天起算，才能把除夕收进来；往后挪一天就收不到。
      final fromNewYearEve = CalendarEngine.lunarFestivalsInRange(
        DateTime(2025, 1, 28),
        2,
      );
      expect(fromNewYearEve.keys, [
        DateTime(2025, 1, 28),
        DateTime(2025, 1, 29),
      ]);

      // 端午 = 2025-05-31，正好是 2025-05-02 + 29 天。
      // 29 天窗口止于 05-30 装不下它，30 天窗口才收进来，
      // 即 from + days 当天被排除在外。
      final beforeDragonBoat = CalendarEngine.lunarFestivalsInRange(
        DateTime(2025, 5, 2),
        29,
      );
      expect(beforeDragonBoat.containsKey(DateTime(2025, 5, 31)), isFalse);

      final throughDragonBoat = CalendarEngine.lunarFestivalsInRange(
        DateTime(2025, 5, 2),
        30,
      );
      expect(throughDragonBoat[DateTime(2025, 5, 31)], ['端午节']);
    });

    test('只返回有节日的日期，而不是每天一条', () {
      // [2025-05-02, +30) 覆盖整个五月前段与端午，只有 2025-05-31 端午节。
      final window = CalendarEngine.lunarFestivalsInRange(
        DateTime(2025, 5, 2),
        30,
      );

      expect(window.length, 1);
      expect(window.keys, [DateTime(2025, 5, 31)]);
      expect(window[DateTime(2025, 5, 31)], ['端午节']);

      // 换一个节日密集的窗口：除夕与春节相邻，说明稀疏不是因为整天都查不到节日。
      final busy = CalendarEngine.lunarFestivalsInRange(
        DateTime(2025, 1, 1),
        30,
      );
      expect(busy.keys, contains(DateTime(2025, 1, 28)));
      expect(busy.keys, contains(DateTime(2025, 1, 29)));
      expect(busy.length, lessThan(30));
    });

    test('返回值与内层列表都不可修改', () {
      final window = CalendarEngine.lunarFestivalsInRange(
        DateTime(2025, 5, 2),
        30,
      );
      final names = window[DateTime(2025, 5, 31)]!;

      expect(
        () => window[DateTime(2025, 6, 1)] = ['端午节'],
        throwsUnsupportedError,
      );
      expect(
        () => window.remove(DateTime(2025, 5, 31)),
        throwsUnsupportedError,
      );
      expect(() => window.clear(), throwsUnsupportedError);
      expect(() => names.add('重阳节'), throwsUnsupportedError);
      expect(() => names.clear(), throwsUnsupportedError);
    });

    test('天数取 0 或 1 时不会越界访问', () {
      expect(
        CalendarEngine.lunarFestivalsInRange(DateTime(2025, 1, 29), 0),
        isEmpty,
      );
      // 单日窗口正好套住春节。
      expect(
        CalendarEngine.lunarFestivalsInRange(DateTime(2025, 1, 29), 1).length,
        1,
      );
      // 单日窗口落在无节日的日子上就是空表。
      expect(
        CalendarEngine.lunarFestivalsInRange(DateTime(2025, 1, 30), 1),
        isEmpty,
      );
    });
  });

  group('CalendarEngine.lunarFestivals', () {
    test('同一天不会返回重复的名字', () {
      // 2025 年全年逐天扫一遍：不重名、不含空串。
      // 覆盖一整年才能同时兜住那些只出现一两次的冷门节日。
      var cursor = DateTime(2025, 1, 1);
      var multiNameDays = 0;
      while (cursor.year == 2025) {
        final names = CalendarEngine.lunarFestivals(cursor);
        expect(
          names.toSet().length,
          names.length,
          reason: '$cursor 出现了重复节日名：$names',
        );
        expect(
          names.where((name) => name.isEmpty),
          isEmpty,
          reason: '$cursor 混进了空名字：$names',
        );
        if (names.length > 1) multiNameDays++;
        cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
      }

      // 2025 年确有多节日日（正月初八 = 2025-02-05，谷日 + 顺星节），
      // 所以上面的「不重复」不是靠列表恒为长度 1 蒙混过关。
      expect(multiNameDays, greaterThan(0));
      expect(CalendarEngine.lunarFestivals(DateTime(2025, 2, 5)).length, 2);
    });

    test('同一天重复查询结果一致', () {
      final first = CalendarEngine.lunarFestivals(DateTime(2025, 1, 29));
      final second = CalendarEngine.lunarFestivals(DateTime(2025, 1, 29));

      expect(second, orderedEquals(first));
      expect(second, ['春节']);
    });

    test('带时间的入参会被归一到当天', () {
      expect(
        CalendarEngine.lunarFestivals(DateTime(2025, 1, 29, 23, 59)),
        CalendarEngine.lunarFestivals(DateTime(2025, 1, 29)),
      );
    });
  });

  group('CalendarEngine.approachProgress', () {
    // 6 月 15 日上一轮是 2025-06-15，下一轮 2026-06-15，一个周期 365 天。
    CountdownEvent birthday() => CountdownEvent(
          id: 'annual-birthday',
          title: '固定阳历纪念日',
          date: DateTime(2019, 6, 15),
          recurrence: EventRecurrence.solarYearly,
        );

    test('一次性事件没有进度，界面据此隐藏进度条', () {
      final event = CountdownEvent(
        id: 'one-time',
        title: '只看一次的日程',
        date: DateTime(2026, 6, 15),
      );

      expect(
        CalendarEngine.approachProgress(
          event,
          DateTime(2026, 6, 15),
          DateTime(2026, 1, 1),
        ),
        isNull,
      );
      expect(
        CalendarEngine.approachProgress(
          event,
          DateTime(2026, 6, 15),
          DateTime(2026, 6, 15),
        ),
        isNull,
      );
    });

    test('上一轮当天是 0，目标当天是 1', () {
      final event = birthday();

      expect(
        CalendarEngine.approachProgress(
          event,
          DateTime(2026, 6, 15),
          DateTime(2025, 6, 15),
        ),
        0,
      );
      expect(
        CalendarEngine.approachProgress(
          event,
          DateTime(2026, 6, 15),
          DateTime(2026, 6, 15),
        ),
        1,
      );
    });

    test('周期过半时进度接近一半', () {
      final event = birthday();
      final previous = DateTime(2025, 6, 15);
      final today = DateTime(2025, 12, 15);
      final target = DateTime(2026, 6, 15);

      final progress = CalendarEngine.approachProgress(event, target, today);
      expect(progress, isNotNull);

      // 2025-06-15 到今天正好 183 天，一个周期 365 天。
      expect(CalendarEngine.daysBetween(previous, today), 183);
      expect(CalendarEngine.daysBetween(previous, target), 365);
      expect(progress, closeTo(183 / 365, 1e-9));

      // 半程的容差直接由一个周期有多少天决定：偏一天就偏 1/365。
      expect(progress, closeTo(0.5, 1 / 365));
    });

    test('早于上一轮或晚于目标都夹在 0 到 1 之间', () {
      final event = birthday();
      final target = DateTime(2026, 6, 15);

      // 2024-01-01 早于上一轮 2025-06-15，快照里这一轮还没开始。
      expect(
        CalendarEngine.approachProgress(event, target, DateTime(2024, 1, 1)),
        0,
      );
      // 2027-06-01 已经越过目标。
      expect(
        CalendarEngine.approachProgress(event, target, DateTime(2027, 6, 1)),
        1,
      );
    });

    test('闰日纪念在平年被压到 2 月 28 日后仍然算得出进度', () {
      final event = CountdownEvent(
        id: 'leap-day-progress',
        title: '闰日纪念',
        date: DateTime(2024, 2, 29),
        recurrence: EventRecurrence.solarYearly,
      );
      // 2026-02-28 这一轮的目标，2025-02-28 是被压过的上一轮。
      final progress = CalendarEngine.approachProgress(
        event,
        DateTime(2026, 2, 28),
        DateTime(2025, 8, 15),
      );

      expect(progress, isNotNull);
      expect(progress!.isNaN, isFalse);
      expect(progress, inInclusiveRange(0.0, 1.0));
      // 2025-02-28 到 2025-08-15 是 168 天，一个周期同样是 365 天。
      expect(progress, closeTo(168 / 365, 1e-9));

      // 闰日被压成 2 月 28 日后，这一轮的目标日当天进度是 1，不是 null。
      expect(
        CalendarEngine.approachProgress(
          event,
          DateTime(2026, 2, 28),
          DateTime(2026, 2, 28),
        ),
        1,
      );
    });

    test('农历年度重复也能算进度', () {
      final event = CountdownEvent(
        id: 'lunar-annual',
        title: '农历生日',
        date: DateTime(2024, 2, 10),
        recurrence: EventRecurrence.lunarYearly,
        lunarMonth: 1,
        lunarDay: 1,
      );
      // 上一轮春节 2026-02-17，下一轮 2027-02-06，间隔 354 天。
      final progress = CalendarEngine.approachProgress(
        event,
        DateTime(2027, 2, 6),
        DateTime(2026, 8, 1),
      );

      expect(progress, isNotNull);
      expect(progress, inInclusiveRange(0.0, 1.0));
      expect(progress, closeTo(165 / 354, 1e-9));
      expect(
        CalendarEngine.approachProgress(
          event,
          DateTime(2027, 2, 6),
          DateTime(2027, 2, 6),
        ),
        1,
      );
    });
  });
}
