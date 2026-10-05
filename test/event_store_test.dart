import 'dart:convert';
import 'dart:io';

import 'package:daymark/data/event_store.dart';
import 'package:daymark/models/countdown_event.dart';
import 'package:daymark/models/day_override.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 一份真实的老备份：完全由手写 JSON 字面量构成，没有 `reminderHour` 键，
/// 用来验证版本 1 的兼容路径——测的是兼容性，不是 toMap/fromMap 的往返。
const String _legacyV1Backup = '''
{
  "format": "daymark.backup",
  "version": 1,
  "exportedAt": "2026-01-02T03:04:05.000",
  "events": [
    {
      "id": "legacy-1",
      "title": "老备份里的事件",
      "date": "2026-05-20",
      "recurrence": "lunarYearly",
      "category": "纪念日",
      "note": "备份时还没有提醒时刻这个字段",
      "lunarMonth": 4,
      "lunarDay": 12,
      "reminderDays": 3
    },
    {
      "id": "legacy-2",
      "title": "另一条老事件",
      "date": "2026-06-01",
      "recurrence": "once",
      "category": "目标",
      "note": "",
      "lunarMonth": null,
      "lunarDay": null,
      "reminderDays": -1
    }
  ],
  "overrides": [
    {
      "origin": "holiday:春节:2026-02-15",
      "title": "春节",
      "date": "2026-02-15T00:00:00.000",
      "category": "重要日",
      "note": "老备份的改动记录",
      "reminderDays": -1,
      "hidden": 0
    }
  ]
}
''';

/// `EventStore` 的真实 SQLite 读写覆盖。
///
/// 必须依赖 `pubspec.yaml` 里 dev_dependencies 的 `sqflite_common_ffi`：应用用的是
/// `sqflite` 插件，它在纯 Dart 的 `flutter test` 环境下没有平台通道可用，只有换成
/// ffi 实现（`databaseFactoryFfi`）才能真正建表、执行 SQL、跑事务。
/// 删掉这个 dev_dependency，这个文件就跑不起来。
///
/// 每个用例开一个独立的系统临时目录做库文件，`tearDown` 先 `close()` 再整个删掉，
/// 不共用固定路径：否则同一台机器连跑两次会读到上一次的残留数据，测试就不确定了。
/// 所有日期都写死，不依赖「今天」。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late EventStore store;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('daymark_event_store_test_');
    store = EventStore(databasePath: _dbPath(tempDir));
  });

  tearDown(() async {
    await store.close();
    tempDir.deleteSync(recursive: true);
  });

  /// 另开一个互不干扰的库，用来验证导入/导出这种「全量替换」不会牵连原库。
  Future<EventStore> scratchStore() async {
    final dir =
        Directory.systemTemp.createTempSync('daymark_event_store_test_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final scratch = EventStore(databasePath: _dbPath(dir));
    addTearDown(scratch.close);
    return scratch;
  }

  group('事件读写', () {
    test('allEvents 按日期升序返回', () async {
      // 故意让 id 的字母顺序与日期顺序不一致，这样排序断言才有意义：
      // id 排下来是 b, c, a，日期排下来是 a(03-05), c(07-01), b(12-31)。
      await store.save(_event('b', date: '2026-12-31'));
      await store.save(_event('c', date: '2026-07-01'));
      await store.save(_event('a', date: '2026-03-05'));

      final events = await store.allEvents();

      expect(
        events.map((event) => event.id).toList(),
        ['a', 'c', 'b'],
        reason: '首页按日期排序展示，读出来的顺序必须就是日期顺序，而不是 id 顺序',
      );
    });

    test('保存后读回每个字段都不丢', () async {
      final event = CountdownEvent(
        id: 'full',
        title: '完整字段',
        date: DateTime(2026, 3, 1),
        recurrence: EventRecurrence.lunarYearly,
        category: '生日',
        note: '备注里有换行\n和符号 &',
        lunarMonth: 4,
        lunarDay: 12,
        reminderDays: 3,
        reminderHour: 21,
      );
      await store.save(event);

      final stored = (await store.allEvents()).single;

      expect(stored.id, 'full');
      expect(stored.title, '完整字段');
      expect(stored.date, DateTime(2026, 3, 1));
      expect(stored.recurrence, EventRecurrence.lunarYearly);
      expect(stored.category, '生日');
      expect(stored.note, '备注里有换行\n和符号 &');
      expect(stored.lunarMonth, 4);
      expect(stored.lunarDay, 12);
      expect(stored.reminderDays, 3);
      expect(stored.reminderHour, 21);
    });

    test('农历字段为空与有值都能原样区分', () async {
      await store.save(
        _event('with-lunar', date: '2026-03-01', lunarMonth: 4, lunarDay: 12),
      );
      await store.save(_event('without-lunar', date: '2026-03-02'));

      final stored = {
        for (final event in await store.allEvents()) event.id: event,
      };

      expect(stored['with-lunar']!.lunarMonth, 4);
      expect(stored['with-lunar']!.lunarDay, 12);
      expect(stored['without-lunar']!.lunarMonth, isNull);
      expect(stored['without-lunar']!.lunarDay, isNull);
    });

    test('同一个 id 再次保存是覆盖而不是多出一条', () async {
      await store.save(_event('dup', date: '2026-03-01'));
      await store.save(_event('dup', date: '2026-03-01', title: '改过的标题'));

      final events = await store.allEvents();

      expect(events, hasLength(1));
      expect(events.single.title, '改过的标题');
    });

    test('delete 只删掉指定的那一条', () async {
      await store.save(_event('a', date: '2026-03-01'));
      await store.save(_event('b', date: '2026-03-02'));
      await store.save(_event('c', date: '2026-03-03'));

      await store.delete('b');

      expect(idsOf(await store.allEvents()), {'a': 'a', 'c': 'c'});
    });

    test('deleteEvents 只删掉列出的那些，空列表不动全表', () async {
      for (final id in const ['a', 'b', 'c', 'd']) {
        await store.save(_event(id, date: '2026-03-0${id.codeUnitAt(0) - 96}'));
      }

      await store.deleteEvents(const ['b', 'd']);
      await store.deleteEvents(const []);

      expect(idsOf(await store.allEvents()), {'a': 'a', 'c': 'c'});
    });

    test('批量改分类只作用在列出的 id 上', () async {
      await store.save(_event('a', date: '2026-03-01', category: '重要日'));
      await store.save(_event('b', date: '2026-03-02', category: '重要日'));
      await store.save(_event('c', date: '2026-03-03', category: '纪念日'));

      await store.updateEventsCategory(const ['a', 'b'], '目标');
      await store.updateEventsCategory(const [], '其他');

      final categories = {
        for (final event in await store.allEvents()) event.id: event.category,
      };
      expect(categories, {'a': '目标', 'b': '目标', 'c': '纪念日'});
    });

    test('批量改提前天数只作用在列出的 id 上', () async {
      await store.save(_event('a', date: '2026-03-01'));
      await store.save(_event('b', date: '2026-03-02'));
      await store.save(_event('c', date: '2026-03-03', reminderDays: 7));

      await store.updateEventsReminder(const ['a', 'b'], 3);
      await store.updateEventsReminder(const [], 1);

      final reminders = {
        for (final event in await store.allEvents())
          event.id: event.reminderDays,
      };
      expect(reminders, {'a': 3, 'b': 3, 'c': 7});
    });

    test('replaceAll 全量替换，撤销后就是这个状态', () async {
      await store.save(_event('old', date: '2026-01-01'));
      await store.saveOverride(_override('holiday:元旦:2026-01-01'));

      await store.replaceAll(
        [_event('new', date: '2026-08-08')],
        [_override('festival:2026-08-08:测试')],
      );

      expect(idsOf(await store.allEvents()), {'new': 'new'});
      expect(
        (await store.allOverrides()).map((o) => o.origin).toList(),
        ['festival:2026-08-08:测试'],
      );
    });
  });

  group('内置条目改动记录', () {
    test('保存后能读回全部字段', () async {
      final override = DayOverride(
        origin: 'holiday:春节:2026-02-15',
        title: '春节（改过）',
        date: DateTime(2026, 2, 16),
        category: '纪念日',
        note: '推迟一天',
        reminderDays: 1,
        reminderHour: 8,
        hidden: true,
      );
      await store.saveOverride(override);

      final stored = (await store.allOverrides()).single;

      expect(stored.origin, 'holiday:春节:2026-02-15');
      expect(stored.title, '春节（改过）');
      expect(stored.date, DateTime(2026, 2, 16));
      expect(stored.category, '纪念日');
      expect(stored.note, '推迟一天');
      expect(stored.reminderDays, 1);
      expect(stored.reminderHour, 8);
      expect(stored.hidden, isTrue);
    });

    test('同一个 origin 再次保存是覆盖而不是多出一条', () async {
      await store.saveOverride(_override('holiday:元旦:2026-01-01'));
      await store.saveOverride(
        _override('holiday:元旦:2026-01-01', title: '改过的名字'),
      );

      final overrides = await store.allOverrides();

      expect(overrides, hasLength(1));
      expect(overrides.single.title, '改过的名字');
    });

    test('删除改动记录后对应内置条目回到内置状态', () async {
      await store.saveOverride(_override('holiday:元旦:2026-01-01'));
      await store.saveOverride(_override('holiday:春节:2026-02-15'));
      await store.saveOverride(_override('festival:2026-03-08:妇女节'));

      await store.deleteOverrides(const ['holiday:春节:2026-02-15']);
      await store.deleteOverrides(const []);

      final origins =
          (await store.allOverrides()).map((o) => o.origin).toList()..sort();
      expect(
        origins,
        ['festival:2026-03-08:妇女节', 'holiday:元旦:2026-01-01'],
      );
    });

    test('删除改动记录不影响自己记的事件', () async {
      await store.save(_event('a', date: '2026-03-01'));
      await store.saveOverride(_override('holiday:元旦:2026-01-01'));

      await store.deleteOverrides(const ['holiday:元旦:2026-01-01']);

      expect(await store.allOverrides(), isEmpty);
      expect(idsOf(await store.allEvents()), {'a': 'a'});
    });
  });

  group('分类清单', () {
    test('新建库时按内置分类建好表', () async {
      expect(
        await store.allCategories(),
        ['纪念日', '生日', '目标', '重要日', '其他'],
        reason: '筛选条一上来就得有东西可显示，空清单会让分类筛选完全没法用',
      );
    });

    test('替换后按给定顺序读回', () async {
      await store.replaceCategories(['目标', '纪念日', '自定义']);

      expect(await store.allCategories(), ['目标', '纪念日', '自定义']);
    });

    test('替换是全量替换：不在新清单里的名字会消失', () async {
      await store.replaceCategories(['自定义']);

      expect(await store.allCategories(), ['自定义']);
    });

    test('空清单不写入，保留本机原有的', () async {
      await store.replaceCategories(['自定义']);
      await store.replaceCategories(const []);

      expect(
        await store.allCategories(),
        ['自定义'],
        reason: '空清单会让编辑器一个分类都选不出来，宁可什么都不改',
      );
    });

    test('replaceAll 不带分类时不动本机清单', () async {
      await store.replaceCategories(['自定义']);

      await store.replaceAll(
        [_event('new', date: '2026-08-08')],
        const [],
      );

      expect(await store.allCategories(), ['自定义']);
    });

    test('replaceAll 带上分类时一并回滚', () async {
      await store.replaceCategories(['自定义']);
      await store.replaceCategories(['别的']);

      await store.replaceAll(
        [_event('new', date: '2026-08-08')],
        const [],
        categories: ['自定义'],
      );

      expect(await store.allCategories(), ['自定义']);
    });
  });

  group('排序与封面字段', () {
    test('新记录落库时补上创建时间', () async {
      final before = DateTime.now().millisecondsSinceEpoch;
      await store.save(_eventAt('a', date: '2026-03-01'));

      final stored = (await store.allEvents()).single;

      expect(stored.createdAt, greaterThanOrEqualTo(before));
      expect(stored.coverPath, isNull);
    });

    test('再次保存不会把已有的创建时间冲掉', () async {
      await store.save(_eventAt('a', date: '2026-03-01', createdAt: 1735689600000));

      await store.save(
        _eventAt('a', date: '2026-03-02', title: '改了日期', createdAt: 1735689600000),
      );

      final stored = (await store.allEvents()).single;
      expect(stored.createdAt, 1735689600000);
      expect(stored.title, '改了日期');
    });

    test('createdAt 为 0 的记录落库后拿到当前时刻', () async {
      final before = DateTime.now().millisecondsSinceEpoch;
      await store.save(_event('a', date: '2026-03-01'));

      expect((await store.allEvents()).single.createdAt, greaterThanOrEqualTo(before));
    });

    test('封面文件名能原样往返', () async {
      await store.save(
        _event('a', date: '2026-03-01').copyWith(coverPath: 'cover-a.jpg'),
      );
      await store.saveOverride(
        _override('holiday:元旦:2026-01-01')
            .copyWith(coverPath: 'cover-b.jpg'),
      );

      expect((await store.allEvents()).single.coverPath, 'cover-a.jpg');
      expect((await store.allOverrides()).single.coverPath, 'cover-b.jpg');
    });

    test('空串封面按「没有封面」处理', () {
      final event = CountdownEvent.fromMap({
        'id': 'a',
        'title': '标题',
        'date': '2026-03-01',
        'coverPath': '   ',
      });

      expect(event.coverPath, isNull);
    });

    test('负的创建时间夹到 0，不当成 1969 年', () {
      final event = CountdownEvent.fromMap({
        'id': 'a',
        'title': '标题',
        'date': '2026-03-01',
        'createdAt': -5,
      });

      expect(event.createdAt, 0);
    });

    test('缺少 createdAt 的老数据回落到 0', () {
      final event = CountdownEvent.fromMap({
        'id': 'a',
        'title': '标题',
        'date': '2026-03-01',
      });

      expect(event.createdAt, 0);
      expect(event.coverPath, isNull);
    });
  });

  group('备份导出与导入', () {
    test('导出带正确的信封头', () async {
      await store.save(_event('a', date: '2026-03-01', reminderHour: 20));
      await store.saveOverride(_override('holiday:元旦:2026-01-01'));

      final payload = await store.exportPayload();

      expect(payload['format'], 'daymark.backup');
      expect(payload['version'], 3);
      final events = payload['events']! as List<dynamic>;
      expect(events, hasLength(1));
      expect((events.single! as Map<String, Object?>)['reminderHour'], 20);
      expect(payload['overrides'], hasLength(1));
      expect(
        payload['categories'],
        ['纪念日', '生日', '目标', '重要日', '其他'],
        reason: '分类清单必须跟着记录一起走，否则换机后筛选条上只有内置的几个',
      );
    });

    test('导出的内容能原样导入到另一个库', () async {
      await store.save(
        _event('a', date: '2026-03-01', lunarMonth: 4, lunarDay: 12),
      );
      await store.save(_event('b', date: '2026-04-01', reminderHour: 7));
      await store.saveOverride(_override('holiday:春节:2026-02-15'));
      final payload = await store.exportPayload();

      final target = await scratchStore();
      final count = await target.importPayload(
        jsonDecode(jsonEncode(payload)) as Map<String, dynamic>,
      );

      expect(count, 2);
      final imported = await target.allEvents();
      expect(imported.map((e) => e.id).toList(), ['a', 'b']);
      expect(imported.first.lunarMonth, 4);
      expect(imported.first.lunarDay, 12);
      expect(imported.last.reminderHour, 7);
      expect(
        (await target.allOverrides()).map((o) => o.origin).toList(),
        ['holiday:春节:2026-02-15'],
      );
      expect(
        await target.allCategories(),
        ['纪念日', '生日', '目标', '重要日', '其他'],
      );
    });

    test('导入是全量替换，本地多出来的记录会被清掉', () async {
      await store.save(_event('keep', date: '2026-03-01'));
      await store.saveOverride(_override('holiday:元旦:2026-01-01'));
      final payload = await store.exportPayload();

      await store.save(_event('stray', date: '2026-09-09'));
      await store.saveOverride(_override('festival:2026-03-08:妇女节'));
      await store.importPayload(payload.cast<String, dynamic>());

      expect(idsOf(await store.allEvents()), {'keep': 'keep'});
      expect(
        (await store.allOverrides()).map((o) => o.origin).toList(),
        ['holiday:元旦:2026-01-01'],
      );
    });

    test('版本 1 的老备份照常能导入，提醒时刻回落到默认的 9 点', () async {
      final count = await store.importPayload(
        jsonDecode(_legacyV1Backup) as Map<String, dynamic>,
      );

      expect(count, 2);
      expect(
        await store.allCategories(),
        ['纪念日', '生日', '目标', '重要日', '其他'],
        reason: '老备份没有分类清单，但记录里的分类名必须出现在筛选条上',
      );
      final events = {
        for (final event in await store.allEvents()) event.id: event,
      };
      expect(events['legacy-1']!.title, '老备份里的事件');
      expect(events['legacy-1']!.date, DateTime(2026, 5, 20));
      expect(events['legacy-1']!.recurrence, EventRecurrence.lunarYearly);
      expect(events['legacy-1']!.lunarMonth, 4);
      expect(events['legacy-1']!.reminderDays, 3);
      expect(events['legacy-1']!.reminderHour, 9);
      expect(events['legacy-2']!.lunarMonth, isNull);
      expect(events['legacy-2']!.reminderHour, 9);

      final overrides = await store.allOverrides();
      expect(overrides.single.origin, 'holiday:春节:2026-02-15');
      expect(overrides.single.reminderHour, 9);
      expect(overrides.single.hidden, isFalse);
    });
  });

  group('备份导入的校验', () {
    setUp(() async {
      // 每条用例都从同一份「本机已有数据」出发，才能看出被拒绝的导入
      // 有没有把用户本机的记录动过。
      await store.save(_event('local', date: '2026-02-02', title: '本机事件'));
      await store.saveOverride(_override('holiday:元旦:2026-01-01'));
    });

    Future<void> expectRejected(Map<String, dynamic> payload) async {
      await expectLater(
        store.importPayload(payload),
        throwsA(isA<FormatException>()),
      );
      expect(
        idsOf(await store.allEvents()),
        {'local': '本机事件'},
        reason: '导入被拒时必须整笔回滚，本机记录不能被动过',
      );
      expect(
        (await store.allOverrides()).map((o) => o.origin).toList(),
        ['holiday:元旦:2026-01-01'],
        reason: '导入被拒时内置条目的改动记录也不能被动过',
      );
    }

    test('信封格式不对', () async {
      await expectRejected(_backup(format: 'daymark.other'));
    });

    test('版本号高于当前能读的版本', () async {
      await expectRejected(_backup(version: 99));
    });

    test('events 不是数组', () async {
      await expectRejected(_backup(events: '不是数组'));
    });

    test('事件超过 1000 条', () async {
      await expectRejected(_backup(events: _manyEvents(1001)));
    });

    test('改动记录超过 2000 条', () async {
      await expectRejected(_backup(overrides: _manyOverrides(2001)));
    });

    test('标题为空或只有空白', () async {
      await expectRejected(_backup(events: [_rawEvent('x', title: '')]));
      await expectRejected(_backup(events: [_rawEvent('x', title: '   ')]));
    });

    test('标题超过 80 字', () async {
      await expectRejected(
        _backup(events: [_rawEvent('x', title: List.filled(81, '长').join())]),
      );
    });

    test('事件元素不是对象', () async {
      await expectRejected(_backup(events: ['不是对象']));
    });

    test('存在重复 id', () async {
      await expectRejected(
        _backup(events: [_rawEvent('same'), _rawEvent('same')]),
      );
    });

    test('overrides 不是数组', () async {
      await expectRejected(_backup(overrides: '不是数组'));
    });

    test('分类清单不是数组', () async {
      await expectRejected(_backup(categories: '不是数组'));
    });

    test('分类超过 50 个', () async {
      await expectRejected(_backup(categories: _manyCategories(51)));
    });

    test('分类名是空串或只有空白', () async {
      await expectRejected(_backup(categories: ['纪念日', '']));
      await expectRejected(_backup(categories: ['纪念日', '   ']));
    });

    test('分类名超过 20 字', () async {
      await expectRejected(
        _backup(categories: [List.filled(21, '长').join()]),
      );
    });

    test('分类清单里有重复的名字', () async {
      await expectRejected(_backup(categories: ['生日', '生日']));
    });

    test('分类元素不是字符串', () async {
      await expectRejected(_backup(categories: ['纪念日', 42]));
    });

    test('导入被拒时本机的分类清单也不能被动过', () async {
      await store.replaceCategories(['本机自用的分类']);

      await expectRejected(_backup(categories: ['', '']));

      expect(
        await store.allCategories(),
        ['本机自用的分类'],
        reason: '整份备份被拒，本机的分类清单必须原样保留',
      );
    });

    test('改动记录元素不是对象', () async {
      await expectRejected(_backup(overrides: [123]));
    });

    test('恰好卡在上限时可以导入', () async {
      await store.importPayload(
        _backup(
          events: _manyEvents(1000),
          overrides: _manyOverrides(2000),
          categories: _manyCategories(50),
        ),
      );

      expect(await store.allEvents(), hasLength(1000));
      expect(await store.allOverrides(), hasLength(2000));
      expect(await store.allCategories(), hasLength(50));
    });

    test('恰好 20 字的分类名可以导入', () async {
      await store.importPayload(_backup(categories: [List.filled(20, '长').join()]));

      expect(await store.allCategories(), [List.filled(20, '长').join()]);
    });
  });
}

Map<String, String> idsOf(Iterable<CountdownEvent> events) => {
      for (final event in events) event.id: event.title,
    };

String _dbPath(Directory dir) =>
    '${dir.path}${Platform.pathSeparator}daymark_events.db';

CountdownEvent _event(
  String id, {
  required String date,
  String? title,
  String category = '重要日',
  int? lunarMonth,
  int? lunarDay,
  int reminderDays = -1,
  int reminderHour = 9,
}) {
  return CountdownEvent(
    id: id,
    title: title ?? id,
    date: DateTime.parse(date),
    category: category,
    lunarMonth: lunarMonth,
    lunarDay: lunarDay,
    reminderDays: reminderDays,
    reminderHour: reminderHour,
  );
}

/// 与 [_event] 等价，但能直接给定 createdAt，用来验证「再次保存不冲掉创建时间」。
CountdownEvent _eventAt(
  String id, {
  required String date,
  int createdAt = 0,
  String? title,
}) =>
    _event(id, date: date, title: title).copyWith(createdAt: createdAt);

DayOverride _override(String origin, {String? title}) {
  return DayOverride(
    origin: origin,
    title: title ?? origin,
    date: DateTime(2026, 1, 1),
    category: '重要日',
    note: '',
    reminderDays: -1,
  );
}

Map<String, dynamic> _rawEvent(String id, {String? title}) => {
      'id': id,
      'title': title ?? id,
      'date': '2026-03-01',
      'recurrence': 'once',
      'category': '重要日',
      'note': '',
      'lunarMonth': null,
      'lunarDay': null,
      'reminderDays': -1,
      'reminderHour': 9,
    };

Map<String, dynamic> _rawOverride(String origin) => {
      'origin': origin,
      'title': origin,
      'date': '2026-01-01T00:00:00.000',
      'category': '重要日',
      'note': '',
      'reminderDays': -1,
      'reminderHour': 9,
      'hidden': 0,
    };

List<Map<String, dynamic>> _manyEvents(int count) => List.generate(
      count,
      (index) => _rawEvent('e$index', title: '第 $index 条'),
    );

List<Map<String, dynamic>> _manyOverrides(int count) => List.generate(
      count,
      (index) => _rawOverride('holiday:条目$index:2026-01-01'),
    );

List<String> _manyCategories(int count) =>
    List.generate(count, (index) => '分类$index');

/// 构造一份待导入的备份。字段默认值都取合法值，用例只覆盖自己要改的那一处，
/// 免得每次都把一整份合法结构抄一遍。
Map<String, dynamic> _backup({
  String format = 'daymark.backup',
  int version = 3,
  Object? events = const <Map<String, dynamic>>[],
  Object? overrides = const <Map<String, dynamic>>[],
  Object? categories = const <String>['纪念日', '其他'],
}) =>
    {
      'format': format,
      'version': version,
      'exportedAt': '2026-01-02T03:04:05.000',
      'events': events,
      'overrides': overrides,
      'categories': categories,
    };
