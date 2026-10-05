enum EventRecurrence { once, solarYearly, lunarYearly }

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
      };

  factory CountdownEvent.fromMap(Map<String, Object?> map) {
    final recurrenceName = map['recurrence'] as String? ?? 'once';
    final recurrence = EventRecurrence.values.firstWhere(
      (value) => value.name == recurrenceName,
      orElse: () => EventRecurrence.once,
    );
    final month = map['lunarMonth'];
    final day = map['lunarDay'];
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
    );
  }

  static String dateKey(DateTime date) => _dateKey(date);

  static String _dateKey(DateTime date) =>
      date.year.toString().padLeft(4, '0') +
      '-' +
      date.month.toString().padLeft(2, '0') +
      '-' +
      date.day.toString().padLeft(2, '0');
}
