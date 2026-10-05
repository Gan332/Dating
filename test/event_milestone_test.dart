import 'package:flutter_test/flutter_test.dart';
import 'package:daymark/core/calendar_engine.dart';
import 'package:daymark/models/countdown_event.dart';

void main() {
  group('milestoneFor 一次性事件', () {
    // 2019-06-15 到 2026-06-15 一共 7 个公历年，其中 2019→2020 与 2023→2024 两段
    // 各含一个闰日，所以是 7×365+2 = 2557 天。
    final birthday = CountdownEvent(
      id: 'friend-birthday',
      title: '好友生日',
      date: DateTime(2019, 6, 15),
    );

    test('elapsedDays 从事件最初那年起算，而不是从今年生日起算', () {
      final milestone = CalendarEngine.milestoneFor(
        birthday,
        DateTime(2026, 6, 15),
      );

      expect(milestone, isNotNull);
      expect(milestone!.elapsedDays, 2557);
    });

    test('一次性事件没有周年，也没有第几次', () {
      final milestone = CalendarEngine.milestoneFor(
        birthday,
        DateTime(2026, 6, 15),
      );

      expect(milestone, isNotNull);
      expect(milestone!.anniversary, isNull);
      expect(milestone.cycleCount, isNull);
    });

    test('就是最初那一天的那次发生算 0 天', () {
      final milestone = CalendarEngine.milestoneFor(
        birthday,
        DateTime(2019, 6, 15),
      );

      expect(milestone, isNotNull);
      expect(milestone!.elapsedDays, 0);
    });

    test('elapsedDays 数的是真实日历天，闰日不会被抹掉', () {
      // 2019-06-15 → 2020-06-15 跨过 2020-02-29，是 366 天而不是 365。
      final milestone = CalendarEngine.milestoneFor(
        birthday,
        DateTime(2020, 6, 15),
      );

      expect(milestone, isNotNull);
      expect(milestone!.elapsedDays, 366);
    });
  });

  group('milestoneFor 公历年度重复', () {
    final wedding = CountdownEvent(
      id: 'wedding',
      title: '结婚纪念日',
      date: DateTime(2019, 6, 15),
      recurrence: EventRecurrence.solarYearly,
    );

    test('周年数与次数相等：2019 到 2026 是第 7 个', () {
      final milestone = CalendarEngine.milestoneFor(
        wedding,
        DateTime(2026, 6, 15),
      );

      expect(milestone, isNotNull);
      expect(milestone!.anniversary, 7);
      expect(milestone.cycleCount, 7);
      expect(milestone.elapsedDays, 2557);
    });

    test('周年日当天才算满一年', () {
      final onAnniversary = CalendarEngine.milestoneFor(
        wedding,
        DateTime(2025, 6, 15),
      );
      final dayBefore = CalendarEngine.milestoneFor(
        wedding,
        DateTime(2025, 6, 14),
      );

      expect(onAnniversary, isNotNull);
      expect(onAnniversary!.anniversary, 6);
      // 前一天还没到第 6 个周年，不能因为公历年份到了就先记 6。
      expect(dayBefore, isNotNull);
      expect(dayBefore!.anniversary, 5);
    });

    test('最初那一天是第 0 个周年，不是第 1 个', () {
      final milestone = CalendarEngine.milestoneFor(
        wedding,
        DateTime(2019, 6, 15),
      );

      expect(milestone, isNotNull);
      expect(milestone!.anniversary, 0);
      expect(milestone.cycleCount, 0);
    });
  });

  group('milestoneFor 闰日事件', () {
    // occurrences() 会把 2 月 29 日在平年夹到 2 月 28 日，里程碑必须跟着这个夹取
    // 后的日子走，否则会整整少算一年。
    final leapDay = CountdownEvent(
      id: 'leap-day',
      title: '闰日纪念',
      date: DateTime(2024, 2, 29),
      recurrence: EventRecurrence.solarYearly,
    );

    test('平年夹到 2 月 28 日之后，周年每年照样 +1', () {
      final dates = CalendarEngine.occurrences(
        leapDay,
        DateTime(2024, 1, 1),
        limit: 5,
      );

      expect(dates.length, 4);
      for (var index = 0; index < dates.length; index++) {
        final milestone = CalendarEngine.milestoneFor(leapDay, dates[index]);
        expect(milestone, isNotNull, reason: '第 $index 次发生不该返回 null');
        expect(milestone!.anniversary, index);
        expect(milestone.cycleCount, index);
      }

      // 2024-02-29 → 2025-02-28 是 365 天，再往平年走又是 365 天。
      final first = CalendarEngine.milestoneFor(leapDay, DateTime(2025, 2, 28));
      final second = CalendarEngine.milestoneFor(leapDay, DateTime(2026, 2, 28));
      expect(first, isNotNull);
      expect(first!.elapsedDays, 365);
      expect(second, isNotNull);
      expect(second!.elapsedDays, 730);
    });

    test('2 月 28 日是周年当天，2 月 27 日还不是', () {
      final onAnniversary = CalendarEngine.milestoneFor(
        leapDay,
        DateTime(2025, 2, 28),
      );
      final dayBefore = CalendarEngine.milestoneFor(
        leapDay,
        DateTime(2025, 2, 27),
      );

      expect(onAnniversary, isNotNull);
      expect(onAnniversary!.anniversary, 1);
      expect(dayBefore, isNotNull);
      expect(dayBefore!.anniversary, 0);
    });
  });

  group('milestoneFor 农历年度重复', () {
    // 腊月初一最能说明问题：它跟着农历年首在公历上漂，落在 12 月底时农历年还是
    // 本年，落在次年 1 月底时农历年已经翻页而公历年还没翻。所以两次发生之间可能
    // 隔着两个公历年，却只走过了 1 个农历年——周年必须按农历年算。
    final laNewYearEve = CalendarEngine.lunarDate(2024, 12, 1)!;
    final nextLaNewYearEve = CalendarEngine.lunarDate(2025, 12, 1)!;

    test('腊月初一事件：公历年差是 2，农历周年只有 1', () {
      // 这两个日期在公历上确实隔了两年，下面两条断言就是在钉住这个前提；
      // 万一农历表变了，测试会立刻炸掉，而不是悄悄失去区分力。
      expect(
        CalendarEngine.daysBetween(laNewYearEve, nextLaNewYearEve),
        greaterThan(365),
      );
      expect(nextLaNewYearEve.year - laNewYearEve.year, 2);

      final event = CountdownEvent(
        id: 'lunar-year-end',
        title: '腊月初一',
        date: laNewYearEve,
        recurrence: EventRecurrence.lunarYearly,
        lunarMonth: 12,
        lunarDay: 1,
      );
      final milestone = CalendarEngine.milestoneFor(event, nextLaNewYearEve);

      expect(milestone, isNotNull);
      expect(milestone!.anniversary, 1);
      expect(milestone.cycleCount, 1);
      // 间隔正好是一个农历年的长度：2025 农历年含闰六月，13 个朔望月约 384 天，
      // 既不是 365 也不是 366。
      expect(milestone.elapsedDays, inInclusiveRange(383, 385));
    });

    test('没存农历月日时按原始日期反推，结果与显式存储一致', () {
      final explicit = CountdownEvent(
        id: 'explicit',
        title: '腊月初一',
        date: laNewYearEve,
        recurrence: EventRecurrence.lunarYearly,
        lunarMonth: 12,
        lunarDay: 1,
      );
      final derived = CountdownEvent(
        id: 'derived',
        title: '腊月初一',
        date: laNewYearEve,
        recurrence: EventRecurrence.lunarYearly,
      );

      final fromExplicit =
          CalendarEngine.milestoneFor(explicit, nextLaNewYearEve);
      final fromDerived =
          CalendarEngine.milestoneFor(derived, nextLaNewYearEve);

      expect(fromExplicit, isNotNull);
      expect(fromDerived, isNotNull);
      expect(fromDerived!.anniversary, fromExplicit!.anniversary);
      expect(fromDerived.anniversary, 1);
    });

    test('农历小月没有三十，夹到廿九之后周年照样数得出来', () {
      // lunarDate 在目标农历年没有三十时回退到廿九；两次发生分属相邻农历年，
      // 所以周年必须是 1 而不是 0 或 2。
      final event = CountdownEvent(
        id: 'lunar-day-30',
        title: '腊月三十',
        date: CalendarEngine.lunarDate(2024, 12, 30)!,
        recurrence: EventRecurrence.lunarYearly,
        lunarMonth: 12,
        lunarDay: 30,
      );

      final first = CalendarEngine.milestoneFor(event, event.date);
      final second = CalendarEngine.milestoneFor(
        event,
        CalendarEngine.lunarDate(2025, 12, 30)!,
      );

      expect(first, isNotNull);
      expect(first!.anniversary, 0);
      expect(second, isNotNull);
      expect(second!.anniversary, 1);
    });
  });

  group('milestoneFor 输入讲不通时', () {
    test('发生日早于事件原始日期返回 null', () {
      final event = CountdownEvent(
        id: 'wedding',
        title: '结婚纪念日',
        date: DateTime(2019, 6, 15),
        recurrence: EventRecurrence.solarYearly,
      );

      expect(CalendarEngine.milestoneFor(event, DateTime(2019, 6, 14)), isNull);
    });

    test('农历月日被写坏时返回 null', () {
      final origin = CalendarEngine.lunarDate(2024, 12, 1)!;
      CountdownEvent broken(int? month, int? day) => CountdownEvent(
        id: 'broken',
        title: '坏数据',
        date: origin,
        recurrence: EventRecurrence.lunarYearly,
        lunarMonth: month,
        lunarDay: day,
      );

      expect(CalendarEngine.milestoneFor(broken(0, 1), origin), isNull);
      expect(CalendarEngine.milestoneFor(broken(13, 1), origin), isNull);
      expect(CalendarEngine.milestoneFor(broken(-13, 1), origin), isNull);
      expect(CalendarEngine.milestoneFor(broken(12, 0), origin), isNull);
      expect(CalendarEngine.milestoneFor(broken(12, 31), origin), isNull);
    });

    test('闰月（负月份）是合法数据，不该被当成坏数据挡掉', () {
      final origin = CalendarEngine.lunarDate(2024, 12, 1)!;
      final leapMonthEvent = CountdownEvent(
        id: 'leap-month',
        title: '闰月纪念',
        date: origin,
        recurrence: EventRecurrence.lunarYearly,
        lunarMonth: -6,
        lunarDay: 15,
      );

      expect(CalendarEngine.milestoneFor(leapMonthEvent, origin), isNotNull);
    });
  });

  group('里程碑中文文案', () {
    test('公历年度重复：已过天数 + 周年', () {
      const milestone = EventMilestone(
        elapsedDays: 2557,
        anniversary: 7,
        cycleCount: 7,
      );

      expect(CalendarEngine.milestoneElapsedLabel(milestone), '已经 2557 天');
      expect(CalendarEngine.milestoneAnniversaryLabel(milestone), '第 7 周年');
      expect(CalendarEngine.milestoneCycleLabel(milestone), '第 7 次');
      expect(
        CalendarEngine.milestoneSummary(milestone),
        '已经 2557 天 · 第 7 周年',
      );
    });

    test('第一次发生说「今天就是这一天」，不说「第 0 周年」', () {
      const milestone = EventMilestone(
        elapsedDays: 0,
        anniversary: 0,
        cycleCount: 0,
      );

      expect(
        CalendarEngine.milestoneElapsedLabel(milestone),
        '今天就是这一天',
      );
      expect(CalendarEngine.milestoneAnniversaryLabel(milestone), '');
      expect(CalendarEngine.milestoneCycleLabel(milestone), '第一次');
      expect(CalendarEngine.milestoneSummary(milestone), '今天就是这一天');
    });

    test('一次性事件只报已过天数，其余留空给界面跳过', () {
      const milestone = EventMilestone(elapsedDays: 2557);

      expect(CalendarEngine.milestoneAnniversaryLabel(milestone), '');
      expect(CalendarEngine.milestoneCycleLabel(milestone), '');
      expect(CalendarEngine.milestoneSummary(milestone), '已经 2557 天');
    });

    test('闰日夹到平年之后的天数与周年一起上屏', () {
      final leapDay = CountdownEvent(
        id: 'leap-day',
        title: '闰日纪念',
        date: DateTime(2024, 2, 29),
        recurrence: EventRecurrence.solarYearly,
      );
      final milestone =
          CalendarEngine.milestoneFor(leapDay, DateTime(2025, 2, 28));

      expect(milestone, isNotNull);
      expect(
        CalendarEngine.milestoneSummary(milestone!),
        '已经 365 天 · 第 1 周年',
      );
    });
  });
}
