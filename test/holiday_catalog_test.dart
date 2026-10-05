import 'package:flutter_test/flutter_test.dart';
import 'package:daymark/data/holiday_catalog.dart';

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
}
