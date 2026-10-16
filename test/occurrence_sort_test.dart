import 'package:daymark/core/calendar_engine.dart';
import 'package:daymark/core/occurrence_sort.dart';
import 'package:daymark/models/app_settings.dart';
import 'package:daymark/models/countdown_event.dart';
import 'package:flutter_test/flutter_test.dart';

/// 一条用户自己记的条目。`createdAt` 直接钉在事件上，测试不读时钟。
///
/// 标题一律用 ASCII 单字母：次级键是**码位序**，中文标题的先后（甲 U+7532 排在
/// 乙 U+4E59 后面）读起来会让人以为断言写反了，用 a/b/c 才一眼看得懂。
EventOccurrence _own(
  String title, {
  required int days,
  int createdAt = 0,
  String category = '重要日',
}) {
  return EventOccurrence(
    title: title,
    date: DateTime(2026, 5, 20),
    daysRemaining: days,
    event: CountdownEvent(
      id: title,
      title: title,
      date: DateTime(2026, 5, 20),
      category: category,
      createdAt: createdAt,
    ),
    subtitle: category,
  );
}

/// 一条内置条目：没有 [EventOccurrence.event]，分类只能由控制器给。
EventOccurrence _builtIn(String title, {required int days}) => EventOccurrence(
      title: title,
      date: DateTime(2026, 2, 17),
      daysRemaining: days,
      subtitle: '传统节日',
      origin: 'festival:2026-02-17:$title',
    );

/// 测试里用的分类解析：自己的记录按记录走，内置条目一律算「重要日」。
String _categoryOf(EventOccurrence item) => item.event?.category ?? '重要日';

List<String> _titles(List<EventOccurrence> items) =>
    items.map((item) => item.title).toList();

void main() {
  group('按剩余天数', () {
    test('最近的在最前，同一天的按标题收尾', () {
      final sorted = sortOccurrences(
        [_own('b', days: 30), _own('c', days: 1), _own('a', days: 1)],
        AppSortMode.upcoming,
        categoryOf: _categoryOf,
      );
      expect(_titles(sorted), ['a', 'c', 'b']);
    });

    test('mostRecentFirst 给「已经走过」用：-1 排在 -300 前面', () {
      final sorted = sortOccurrences(
        [
          _own('很久以前', days: -300),
          _own('昨天', days: -1),
          _own('上个月', days: -30),
        ],
        AppSortMode.upcoming,
        categoryOf: _categoryOf,
        mostRecentFirst: true,
      );
      expect(_titles(sorted), ['昨天', '上个月', '很久以前']);
    });
  });

  group('按创建时间', () {
    test('新记的排最前', () {
      final sorted = sortOccurrences(
        [
          _own('old', days: 1, createdAt: 1000),
          _own('new', days: 300, createdAt: 3000),
          _own('older', days: 5, createdAt: 500),
        ],
        AppSortMode.createdAt,
        categoryOf: _categoryOf,
      );
      expect(_titles(sorted), ['new', 'old', 'older']);
    });

    test('没有创建时间的老记录排在最后，而不是被当成 1970 年挤到最前', () {
      final sorted = sortOccurrences(
        [
          _own('stale-b', days: 1),
          _own('fresh', days: 1, createdAt: 2000),
          _own('stale-a', days: 1),
        ],
        AppSortMode.createdAt,
        categoryOf: _categoryOf,
      );
      expect(_titles(sorted), ['fresh', 'stale-a', 'stale-b']);
    });

    test('内置条目不是用户建的，一律排最后', () {
      final sorted = sortOccurrences(
        [
          _builtIn('春节', days: 2),
          _own('new', days: 9, createdAt: 2000),
        ],
        AppSortMode.createdAt,
        categoryOf: _categoryOf,
      );
      expect(_titles(sorted), ['new', '春节']);
    });
  });

  group('按分类', () {
    const order = ['纪念日', '生日', '重要日'];

    test('按清单顺序排，同分类内按标题', () {
      final sorted = sortOccurrences(
        [
          _own('d', days: 1, category: '重要日'),
          _own('b', days: 2, category: '纪念日'),
          _own('a', days: 3, category: '纪念日'),
          _own('c', days: 4, category: '生日'),
        ],
        AppSortMode.category,
        categoryOf: _categoryOf,
        categoryOrder: order,
      );
      expect(_titles(sorted), ['a', 'b', 'c', 'd']);
    });

    test('清单里没有的分类（被删掉的老名字）排最后', () {
      final sorted = sortOccurrences(
        [
          _own('orphan', days: 1, category: '早就删了'),
          _own('normal', days: 9, category: '生日'),
          _builtIn('传统节日', days: 3),
        ],
        AppSortMode.category,
        categoryOf: _categoryOf,
        categoryOrder: order,
      );
      // 内置条目由 _categoryOf 算成「重要日」排第二；孤儿分类找不到，排最后。
      expect(_titles(sorted), ['normal', '传统节日', 'orphan']);
    });
  });

  group('通用约定', () {
    test('返回值不可修改', () {
      final sorted = sortOccurrences(
        [_own('a', days: 1)],
        AppSortMode.upcoming,
        categoryOf: _categoryOf,
      );
      expect(() => sorted.clear(), throwsUnsupportedError);
    });

    test('不改动传进来的列表', () {
      final source = [_own('b', days: 2), _own('a', days: 1)];
      sortOccurrences(source, AppSortMode.upcoming, categoryOf: _categoryOf);
      expect(_titles(source), ['b', 'a'], reason: '排序要作用在副本上');
    });
  });

  group('排序设置的持久化', () {
    test('存下来能原样读回', () {
      const settings = AppSettings(sortMode: AppSortMode.category);
      expect(settings.toJson()['sortMode'], 'category');
      expect(
        AppSettings.fromJson(settings.toJson()).sortMode,
        AppSortMode.category,
      );
    });

    test('老设置没有这个键时回落到默认', () {
      final json = const AppSettings().toJson()..remove('sortMode');
      expect(AppSettings.fromJson(json).sortMode, AppSortMode.upcoming);
    });

    test('写坏的值同样回落，而不是崩在启动里', () {
      final wrong = const AppSettings().toJson()..['sortMode'] = '按运气排';
      expect(AppSettings.fromJson(wrong).sortMode, AppSortMode.upcoming);

      final nulled = const AppSettings().toJson()..['sortMode'] = null;
      expect(AppSettings.fromJson(nulled).sortMode, AppSortMode.upcoming);
    });
  });
}
