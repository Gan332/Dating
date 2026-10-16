import '../models/app_settings.dart';
import 'calendar_engine.dart';

/// 按用户选的模式整理一组列表条目。
///
/// 纯函数：不读时钟、不碰控制器，界面与测试用同一份口径。三种模式都以标题作为
/// 次级键，同键条目（同一天、同一秒建的两条）的位置才是确定的，不会每次重建
/// 都换一个顺序。
///
/// [categoryOf] 必须由调用方给（界面传 `AppController.categoryOf`）：内置条目的
/// 分类存在改动记录里，函数这一层拿不到，在这里现推一个就成了第二套口径。
/// [categoryOrder] 是分类清单的顺序，也就是界面上的展示顺序。
/// [mostRecentFirst] 只影响 [AppSortMode.upcoming]，给「已经走过」那一段用：
/// 那边的剩余天数是负数，-1（昨天）要排在 -300（去年）前面。
///
/// 返回值不可修改。
List<EventOccurrence> sortOccurrences(
  List<EventOccurrence> items,
  AppSortMode mode, {
  required String Function(EventOccurrence item) categoryOf,
  List<String> categoryOrder = const [],
  bool mostRecentFirst = false,
}) {
  // 用 switch 表达式而不是 if/else：以后加了新模式，这里会因穷尽性检查直接编译
  // 不过，而不是安静地落进 else 里按剩余天数排。
  return switch (mode) {
    AppSortMode.upcoming => _byRemaining(items, mostRecentFirst),
    AppSortMode.createdAt => _byCreatedAt(items),
    AppSortMode.category => _byCategory(items, categoryOf, categoryOrder),
  };
}

List<EventOccurrence> _byRemaining(
  List<EventOccurrence> items, {
  required bool mostRecentFirst,
}) {
  final sorted = List<EventOccurrence>.of(items);
  if (mostRecentFirst) {
    sorted.sort((a, b) => _tie(b.daysRemaining.compareTo(a.daysRemaining), a, b));
  } else {
    sorted.sort((a, b) => _tie(a.daysRemaining.compareTo(b.daysRemaining), a, b));
  }
  return List<EventOccurrence>.unmodifiable(sorted);
}

List<EventOccurrence> _byCreatedAt(List<EventOccurrence> items) {
  final sorted = List<EventOccurrence>.of(items);
  sorted.sort((a, b) => _tie(_createdAtCompare(a, b), a, b));
  return List<EventOccurrence>.unmodifiable(sorted);
}

List<EventOccurrence> _byCategory(
  List<EventOccurrence> items,
  String Function(EventOccurrence item) categoryOf,
  List<String> categoryOrder,
) {
  final sorted = List<EventOccurrence>.of(items);
  sorted.sort((a, b) =>
      _tie(_categoryCompare(a, b, categoryOf, categoryOrder), a, b));
  return List<EventOccurrence>.unmodifiable(sorted);
}

/// 主键相等时用标题收尾，保证顺序稳定。
int _tie(int primary, EventOccurrence a, EventOccurrence b) =>
    primary != 0 ? primary : a.title.compareTo(b.title);

/// 「创建时间」的取值：内置条目不是用户建的，一律算 0。
int _createdAtOf(EventOccurrence item) => item.event?.createdAt ?? 0;

/// 新记的排最前。没有创建时间的老记录（0）一律排最后，而不是被当成 1970 年
/// 挤到最前面——这正是 `createdAt` 那条约定要的效果。
int _createdAtCompare(EventOccurrence a, EventOccurrence b) {
  final left = _createdAtOf(a);
  final right = _createdAtOf(b);
  if (left == 0 && right == 0) return 0;
  if (left == 0) return 1;
  if (right == 0) return -1;
  return right.compareTo(left);
}

/// 按分类清单的顺序排。清单里没有的分类（改名后被删掉的老名字）排最后。
int _categoryCompare(
  EventOccurrence a,
  EventOccurrence b,
  String Function(EventOccurrence item) categoryOf,
  List<String> categoryOrder,
) {
  final left = categoryOrder.indexOf(categoryOf(a));
  final right = categoryOrder.indexOf(categoryOf(b));
  return (left < 0 ? categoryOrder.length : left)
      .compareTo(right < 0 ? categoryOrder.length : right);
}
