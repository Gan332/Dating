import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

typedef _NativeDaysBetween = ffi.Int64 Function(
  ffi.Int32,
  ffi.Int32,
  ffi.Int32,
  ffi.Int32,
  ffi.Int32,
  ffi.Int32,
);
typedef _DartDaysBetween = int Function(int, int, int, int, int, int);

class RustDateCore {
  RustDateCore._();

  static final _DartDaysBetween? _native = _loadNative();

  static _DartDaysBetween? _loadNative() {
    if (!Platform.isAndroid) return null;
    try {
      return ffi.DynamicLibrary.open('libdaymark_core.so')
          .lookupFunction<_NativeDaysBetween, _DartDaysBetween>(
        'daymark_days_between',
      );
    } on ArgumentError {
      return null;
    } on Exception {
      return null;
    }
  }

  static int daysBetween(DateTime from, DateTime to) {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    final calculate = _native;
    if (calculate != null) {
      final result = calculate(
        start.year,
        start.month,
        start.day,
        end.year,
        end.month,
        end.day,
      );
      if (result != -0x8000000000000000) return result;
    }
    return DateTime.utc(end.year, end.month, end.day)
        .difference(DateTime.utc(start.year, start.month, start.day))
        .inDays;
  }
}
