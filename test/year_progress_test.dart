import 'package:daymark/core/year_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('普通年：年初与年末的天数都对得上', () {
    final start = YearProgress.of(DateTime(2026, 1, 1));
    expect(start.dayOfYear, 1);
    expect(start.totalDays, 365);
    expect(start.daysLeft, 364);
    expect(start.progress, closeTo(1 / 365, 1e-9));

    final end = YearProgress.of(DateTime(2026, 12, 31));
    expect(end.dayOfYear, 365);
    expect(end.daysLeft, 0);
    expect(end.progress, 1);
  });

  test('闰年有 366 天', () {
    final leap = YearProgress.of(DateTime(2028, 3, 1));
    expect(leap.totalDays, 366);
    expect(leap.dayOfYear, 61);
    expect(leap.daysLeft, 305);
  });

  test('跨过零点后进入新的一年', () {
    final newYear = YearProgress.of(DateTime(2027, 1, 1));
    expect(newYear.year, 2027);
    expect(newYear.dayOfYear, 1);
    expect(newYear.totalDays, 365);
  });
}
