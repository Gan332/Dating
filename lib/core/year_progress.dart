import 'calendar_engine.dart';

/// 今年已经走到第几天、还剩多少天。
class YearProgress {
  const YearProgress({
    required this.year,
    required this.dayOfYear,
    required this.totalDays,
    required this.daysLeft,
  });

  final int year;

  /// 今天是今年的第几天，从 1 开始。
  final int dayOfYear;

  /// 今年一共有多少天，闰年 366。
  final int totalDays;

  /// 距离今年最后一天还有多少天。
  final int daysLeft;

  /// 0~1 的年度进度。
  double get progress => dayOfYear / totalDays;

  /// 按传入时间算出的年度进度；1 月 1 日为第 1 天。
  static YearProgress of(DateTime now) {
    final start = DateTime(now.year);
    final today = CalendarEngine.dateOnly(now);
    final nextYear = DateTime(now.year + 1);
    final totalDays = CalendarEngine.daysBetween(start, nextYear);
    final dayOfYear = CalendarEngine.daysBetween(start, today) + 1;
    return YearProgress(
      year: now.year,
      dayOfYear: dayOfYear,
      totalDays: totalDays,
      daysLeft: totalDays - dayOfYear,
    );
  }
}
