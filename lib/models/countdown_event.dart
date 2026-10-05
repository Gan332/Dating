enum EventRecurrence { once, solarYearly, lunarYearly }

/// 内置的分类选项。
///
/// 新装与老库升级都以它为起点，用户随后可以在「重要日」页自己增删改
/// （见 [EventStore.replaceCategories]）。这里保留它是为了让模型层不必
/// 反向依赖数据层，也给测试一个不碰数据库就能用的起步清单。
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
    this.createdAt = 0,
    this.coverPath,
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

  /// 创建时的毫秒时间戳，只用于「按创建时间」这一种排序。
  ///
  /// 存成整数而不是 [DateTime]，是为了跟 [reminderHour] 一样用一个标量跨时区表达。
  /// 0 表示「不知道什么时候创建的」——老记录与旧备份都没有这个字段。这类记录在
  /// 按创建时间排序时一律排在最后，而不是被当成 1970 年挤到最前面。
  final int createdAt;

  /// 封面图在应用私有目录里的文件名（不含路径）；为空表示没有封面图。
  ///
  /// 只存文件名：应用私有目录的具体路径在换机、重装、被系统迁移之后都会变，
  /// 把绝对路径存进数据库等于把图永久丢在旧机器上。
  final String? coverPath;

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
    int? createdAt,
    String? coverPath,
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
      createdAt: createdAt ?? this.createdAt,
      coverPath: coverPath ?? this.coverPath,
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
        'createdAt': createdAt,
        'coverPath': coverPath,
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
    // 老记录与旧备份都没有 createdAt，一律回落 0（含义见字段注释）。
    // 负数的时间戳没有意义，夹到 0，免得手改过的备份把 1969 年的记录排到最前。
    final createdAt = (map['createdAt'] as num?)?.toInt() ?? 0;
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
      createdAt: createdAt < 0 ? 0 : createdAt,
      // 空串按「没有封面」处理：老数据里没有这个键时读出来是 null，
      // 手改过的备份可能留个空串，两者含义相同。
      coverPath: _cleanPath(map['coverPath']),
    );
  }

  /// 封面路径的空值归一：null 与空串都表示没有封面。
  static String? _cleanPath(Object? raw) {
    final text = raw as String?;
    if (text == null || text.trim().isEmpty) return null;
    return text;
  }

  static String dateKey(DateTime date) => _dateKey(date);

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
