/// 用户对内置条目（官方节假日、传统节日）的改动。
///
/// 内置数据来自公布的放假安排与农历算法，本身不落库；这里只记录「改了什么」，
/// 用 [origin] 稳定地关联回对应的内置条目，取消改动即恢复内置数据。
class DayOverride {
  const DayOverride({
    required this.origin,
    required this.title,
    required this.date,
    required this.category,
    required this.note,
    required this.reminderDays,
    this.hidden = false,
  });

  /// 内置条目的稳定标识，例如 `holiday:春节:2026-02-15`。
  final String origin;

  /// 改动后的名称。
  final String title;

  /// 改动后的日期。
  final DateTime date;

  final String category;
  final String note;

  /// -1 表示不提醒。
  final int reminderDays;

  /// 是否把这条内置条目从界面里隐藏。
  final bool hidden;

  DayOverride copyWith({
    String? title,
    DateTime? date,
    String? category,
    String? note,
    int? reminderDays,
    bool? hidden,
  }) {
    return DayOverride(
      origin: origin,
      title: title ?? this.title,
      date: date ?? this.date,
      category: category ?? this.category,
      note: note ?? this.note,
      reminderDays: reminderDays ?? this.reminderDays,
      hidden: hidden ?? this.hidden,
    );
  }

  Map<String, Object?> toMap() => {
        'origin': origin,
        'title': title,
        'date': date.toIso8601String(),
        'category': category,
        'note': note,
        'reminderDays': reminderDays,
        'hidden': hidden ? 1 : 0,
      };

  factory DayOverride.fromMap(Map<String, Object?> map) {
    final raw = DateTime.parse(map['date']! as String);
    return DayOverride(
      origin: map['origin']! as String,
      title: map['title']! as String,
      date: DateTime(raw.year, raw.month, raw.day),
      category: (map['category'] as String?) ?? '重要日',
      note: (map['note'] as String?) ?? '',
      reminderDays: (map['reminderDays'] as num?)?.toInt() ?? -1,
      hidden: ((map['hidden'] as num?)?.toInt() ?? 0) == 1,
    );
  }
}
