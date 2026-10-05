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

/// 某一次发生相对事件「最初那一天」已经过去了多少。
///
/// 倒数日只回答「还有几天」，可纪念日、生日这类记录真正让人在意的是另一半：
/// 这件事已经持续了多久、第几个周年、今天是第几次发生。这些文案要用的算术
/// 全部收在这里，界面层只负责把字符串摆上去——否则首页、日历页、详情页各写
/// 一遍加减法，很容易算出三个不一样的数字。
class EventMilestone {
  const EventMilestone({
    required this.elapsedDays,
    this.anniversary,
    this.cycleCount,
  });

  /// 从事件最初的 [CountdownEvent.date] 到本次发生，一共过了多少天。
  ///
  /// 始终从原始日期起算，而不是从「上一次发生」起算：一条 2019 年建的好友生日，
  /// 在 2026 年那天要报两千五百多天，而不是从今年生日重新计数的 0。
  final int elapsedDays;

  /// 第几周年；一次性事件没有周年，取 null。
  final int? anniversary;

  /// 到本次发生为止累计第几次；算不出来时取 null。
  ///
  /// 年度重复事件里它与 [anniversary] 恒等，因为「一次周期」就是一个周年：
  /// 公历重复按公历年算，农历重复按农历年算。一次性事件只有一次发生，
  /// 却谈不上「第几次」，同样为 null。
  final int? cycleCount;
}

class CalendarEngine {
  /// 官方节假日区间的稳定标识。区间内某一天都指回同一个内置条目。
  static String holidayOrigin(String name, DateTime start) =>
      'holiday:$name:${CountdownEvent.dateKey(start)}';

  /// 传统节日的稳定标识。
  static String festivalOrigin(DateTime date, String name) =>
      'festival:${CountdownEvent.dateKey(date)}:$name';

  /// 农历换算的按日缓存，键是 yyyyMMdd。
  ///
  /// 农历与某一天的对应关系是固定的，不会随时间变化，所以可以放心缓存。
  /// 首页一次 build 要扫 180 天、日历页一次要渲染 42 个格子，每次都新建
  /// [Lunar] 对象开销很大；这里把结果留下，重复 build 直接命中。
  static final Map<int, Lunar> _lunarCache = {};

  /// 每天的节日名，单独存一份免得每次都重新拼装去重。
  static final Map<int, List<String>> _festivalCache = {};

  /// 缓存上限。正常使用下一天只会新增一条，留足余量即可；触顶就整体丢弃，
  /// 宁可重算也不要让长期运行的应用一直占着内存。
  static const int _cacheLimit = 4096;

  static DateTime dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static int daysBetween(DateTime from, DateTime to) =>
      RustDateCore.daysBetween(dateOnly(from), dateOnly(to));

  /// 扫描 [from] 起连续 [days] 天里所有带传统节日的日期。
  ///
  /// 只返回真的有节日的日期，避免调用方遍历 181 个空结果。返回值按日期升序，
  /// 内部列表不可修改。
  static Map<DateTime, List<String>> lunarFestivalsInRange(
    DateTime from,
    int days,
  ) {
    final start = dateOnly(from);
    final found = <DateTime, List<String>>{};
    for (var offset = 0; offset < days; offset++) {
      final date = start.add(Duration(days: offset));
      final names = lunarFestivals(date);
      if (names.isNotEmpty) found[date] = names;
    }
    return Map.unmodifiable(found);
  }

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

  /// 距离 [target] 这天已经走过的比例（0~1）。
  ///
  /// 只有年度重复的事件算得出来：一个周期就是上一次发生到这一次发生之间的
  /// 间隔，除掉已过的天数即可。一次性事件和内置条目（官方假期、传统节日）
  /// 没有「上一次」可依，返回 null——调用方应当据此隐藏进度条，而不是编一个
  /// 与数据无关的数字出来。
  static double? approachProgress(
    CountdownEvent event,
    DateTime target,
    DateTime today,
  ) {
    if (event.recurrence == EventRecurrence.once) return null;
    // 从目标日期前一年开始找，才能同时拿到「上一次」与「这一次」。
    final window = occurrences(
      event,
      dateOnly(target).subtract(const Duration(days: 366)),
      limit: 3,
    );
    final goal = dateOnly(target);
    final index = window.indexOf(goal);
    if (index < 1) return null;

    final previous = window[index - 1];
    final span = daysBetween(previous, goal);
    if (span <= 0) return null;
    final elapsed = daysBetween(previous, dateOnly(today));
    return (elapsed / span).clamp(0.0, 1.0);
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

  /// 某一天的传统节日名（不含节气）。结果按日缓存，重复调用不会重复换算。
  ///
  /// 农历库会把同一天的多个节日合成一个列表，这里按首次出现去重，
  /// 调用方拿到的就是「这一天有哪几个节日」。
  static List<String> lunarFestivals(DateTime date) {
    final day = dateOnly(date);
    final key = day.year * 10000 + day.month * 100 + day.day;
    final cached = _festivalCache[key];
    if (cached != null) return cached;
    final lunar = _lunarOf(day);
    final names = <String>[];
    for (final name in [...lunar.getFestivals(), ...lunar.getOtherFestivals()]) {
      if (name.isNotEmpty && !names.contains(name)) names.add(name);
    }
    final result = List<String>.unmodifiable(names);
    if (_festivalCache.length >= _cacheLimit) _festivalCache.clear();
    _festivalCache[key] = result;
    return result;
  }

  /// 取某一天的农历对象，命中按日缓存。
  ///
  /// 日历页一次要渲染 42 个格子，节日名、农历日、节气都从这里取；
  /// 不缓存的话每次重建都要为同一天反复构造 [Lunar]。
  static Lunar _lunarOf(DateTime date) {
    final day = dateOnly(date);
    final key = day.year * 10000 + day.month * 100 + day.day;
    final cached = _lunarCache[key];
    if (cached != null) return cached;

    final lunar = Lunar.fromDate(day);
    if (_lunarCache.length >= _cacheLimit) _lunarCache.clear();
    _lunarCache[key] = lunar;
    return lunar;
  }

  static String lunarDayLabel(DateTime date) {
    final lunar = _lunarOf(date);
    if (lunar.getDay() == 1) return lunar.getMonthInChinese();
    return lunar.getDayInChinese();
  }

  static String solarTerm(DateTime date) {
    final lunar = _lunarOf(date);
    final jie = lunar.getJie();
    return jie.isNotEmpty ? jie : lunar.getQi();
  }

  /// 计算 [event] 在 [occurrence] 那一天的里程碑。
  ///
  /// [occurrence] 应当是 [occurrences] 给出的真实发生日。[elapsedDays] 永远从事件
  /// 最初的 [CountdownEvent.date] 起算，所以一条 2019 年的生日在 2026 年那天报的是
  /// 两千五百多天，而不是从今年生日重新计数的 0。
  ///
  /// 返回 null 只有两种情形，都意味着输入本身讲不通，界面层应当把这块文案藏掉，
  /// 而不是编一个与数据无关的数字出来：
  /// 1. [occurrence] 早于事件最初那一天——「已经过去多少天」无从谈起；
  /// 2. 农历重复事件的农历月或日被写坏（月份不在 ±1..12、日不在 1..30），
  ///    既定位不了周年，也定位不了发生日。
  static EventMilestone? milestoneFor(
    CountdownEvent event,
    DateTime occurrence,
  ) {
    final origin = dateOnly(event.date);
    final target = dateOnly(occurrence);
    if (target.isBefore(origin)) return null;
    final elapsedDays = daysBetween(origin, target);

    switch (event.recurrence) {
      case EventRecurrence.once:
        // 一次性事件只发生一次，谈不上周年，也谈不上「第几次」。
        return EventMilestone(elapsedDays: elapsedDays);
      case EventRecurrence.solarYearly:
        // 公历重复：一个公历年就是一个周年，次数与周年恒等。
        final solarYears = _solarAnniversaryYears(origin, target);
        return EventMilestone(
          elapsedDays: elapsedDays,
          anniversary: solarYears,
          cycleCount: solarYears,
        );
      case EventRecurrence.lunarYearly:
        final originLunar = _lunarOf(origin);
        // 与 occurrences 保持同一套兜底：没存农历月日就按原始日期反推，
        // 两边算出来的必须是同一个日子。
        final month = event.lunarMonth ?? originLunar.getMonth();
        final day = event.lunarDay ?? originLunar.getDay();
        // 月份为负代表闰月；越界说明数据被写坏了。
        if (month == 0 || month.abs() > 12 || day < 1 || day > 30) return null;
        // 农历周年必须按农历年算，不能拿公历年差凑数：腊月事件会跟着农历年首
        // 在公历 12 月底到次年 1 月底之间来回漂，同样是「一个农历年」，两次发生
        // 在公历上却可能隔开两年（2024-12-30 与 2026-01-18）。同一个农历月日在一个
        // 农历年里只会发生一次，所以周年数 = 目标那天的农历年 − 原始那天的农历年。
        final lunarYears = _lunarOf(target).getYear() - originLunar.getYear();
        final cycles = lunarYears < 0 ? 0 : lunarYears;
        return EventMilestone(
          elapsedDays: elapsedDays,
          anniversary: cycles,
          cycleCount: cycles,
        );
    }
  }

  /// 「已经 2557 天」。
  ///
  /// 中文里「天」是量词，数字直接跟在后面读最顺，所以这句固定写在计算层，
  /// 界面层不要再自己拼一遍。
  static String milestoneElapsedLabel(EventMilestone milestone) =>
      milestone.elapsedDays == 0
      ? '今天就是这一天'
      : '已经 ${milestone.elapsedDays} 天';

  /// 「第 7 周年」。
  ///
  /// 没有周年信息（一次性事件）时返回空串，界面层跳过即可。周年数为 0 说明
  /// 就是最初那一天，没有「第 0 周年」这种说法，同样返回空串。
  static String milestoneAnniversaryLabel(EventMilestone milestone) {
    final years = milestone.anniversary;
    if (years == null || years <= 0) return '';
    return '第 $years 周年';
  }

  /// 「第 3 次」。
  ///
  /// 没有次数信息时返回空串。第一次发生说「第一次」而不是「第 0 次」。
  static String milestoneCycleLabel(EventMilestone milestone) {
    final count = milestone.cycleCount;
    if (count == null) return '';
    return count == 0 ? '第一次' : '第 $count 次';
  }

  /// 一行摘要：已过天数 + 周年，中间用「 · 」连接；首次发生只报天数。
  ///
  /// 年度重复事件的「次数」与「周年」恒等（见 [EventMilestone.cycleCount]），
  /// 摘要里只留周年一项，免得同一行出现「第 7 周年 · 第 7 次」这种重复话；
  /// 需要单独展示次数的界面请直接用 [milestoneCycleLabel]。
  static String milestoneSummary(EventMilestone milestone) =>
      [milestoneElapsedLabel(milestone), milestoneAnniversaryLabel(milestone)]
          .where((part) => part.isNotEmpty)
          .join(' · ');

  /// 从 [origin] 到 [target] 之间走过的整年数（公历）。
  ///
  /// 不能直接取 target.year - origin.year 再配 [DateTime] 比较：2 月 29 日在平年
  /// 被夹到 2 月 28 日，这一天按民用习惯已经算过周年，可拿原始日期去比会整整
  /// 少算一年（2024-02-29 → 2025-02-28 会被判成 0 周年）。所以两边都按夹取后的
  /// 周年日来比：周年日还没到，就退一年。
  static int _solarAnniversaryYears(DateTime origin, DateTime target) {
    var years = target.year - origin.year;
    while (years > 0 &&
        _solarAnniversaryDate(origin, origin.year + years).isAfter(target)) {
      years--;
    }
    return years;
  }

  /// [origin] 在 [year] 年的周年日；月末会被夹到当月最后一天。
  static DateTime _solarAnniversaryDate(DateTime origin, int year) {
    final lastDay = DateTime(year, origin.month + 1, 0).day;
    return DateTime(
      year,
      origin.month,
      origin.day > lastDay ? lastDay : origin.day,
    );
  }
}
