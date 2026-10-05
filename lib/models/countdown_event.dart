enum EventRecurrence { once, solarYearly, lunarYearly }

/// 内置的分类选项，编辑器与批量修改共用。
const List<String> kEventCategories = ['纪念日', '生日', '目标', '重要日', '其他'];

class CountdownEvent {
  const CountdownEvent({
    required this.id,
    required this.title,
    required this.date,
    this.recurrence = EventRecurrence.once,
    this.category = '重要日',
    this.note = '',
    this.lunarMonth,
    this.lunarDay,
    this.reminderDays = -1,
    this.reminderHour = 9,
  });

  final String id;
  final String title;
  final DateTime date;
  final EventRecurrence recurrence;
  final String category;
  final String note;
  final int? lunarMonth;
  final int? lunarDay;
  final int reminderDays;

  /// 提醒当天的几点（0..23）。默认早上 9 点：多数倒数日是「当天早上才想起来看一眼」，
  /// 半夜推送只会显得打扰。存成整数而不是 [DateTime]，是为了让 SQL 列与备份 JSON
  /// 都用一个标量表达，跨时区也不会把「上午 9 点」漂移成别的时间。
  final int reminderHour;

  CountdownEvent copyWith({
    String? id,
    String? title,
    DateTime? date,
    EventRecurrence? recurrence,
    String? category,
    String? note,
    int? lunarMonth,
    int? lunarDay,
    int? reminderDays,
    int? reminderHour,
  }) {
    return CountdownEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      date: date ?? this.date,
      recurrence: recurrence ?? this.recurrence,
      category: category ?? this.category,
      note: note ?? this.note,
      lunarMonth: lunarMonth ?? this.lunarMonth,
      lunarDay: lunarDay ?? this.lunarDay,
      reminderDays: reminderDays ?? this.reminderDays,
      reminderHour: reminderHour ?? this.reminderHour,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'date': _dateKey(date),
        'recurrence': recurrence.name,
        'category': category,
        'note': note,
        'lunarMonth': lunarMonth,
        'lunarDay': lunarDay,
        'reminderDays': reminderDays,
        'reminderHour': reminderHour,
      };

  factory CountdownEvent.fromMap(Map<String, Object?> map) {
    final recurrenceName = map['recurrence'] as String? ?? 'once';
    final recurrence = EventRecurrence.values.firstWhere(
      (value) => value.name == recurrenceName,
      orElse: () => EventRecurrence.once,
    );
    final month = map['lunarMonth'];
    final day = map['lunarDay'];
    // 旧备份没有这个字段，回落到 9 点；再夹一次范围，手改过的备份也不能把
    // 30 点这种非法值带进数据库。
    final hour = ((map['reminderHour'] as num?)?.toInt() ?? 9).clamp(0, 23);
    return CountdownEvent(
      id: map['id'] as String,
      title: map['title'] as String,
      date: DateTime.parse(map['date'] as String),
      recurrence: recurrence,
      category: map['category'] as String? ?? '重要日',
      note: map['note'] as String? ?? '',
      lunarMonth: month == null ? null : (month as num).toInt(),
      lunarDay: day == null ? null : (day as num).toInt(),
      reminderDays: (map['reminderDays'] as num?)?.toInt() ?? -1,
      reminderHour: hour,
    );
  }

  static String dateKey(DateTime date) => _dateKey(date);

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
