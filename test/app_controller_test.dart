import 'dart:async';

import 'package:daymark/app_controller.dart';
import 'package:daymark/data/event_store.dart';
import 'package:daymark/data/holiday_repository.dart';
import 'package:daymark/models/holiday_data.dart';
import 'package:daymark/data/settings_store.dart';
import 'package:daymark/models/app_settings.dart';
import 'package:daymark/models/countdown_event.dart';
import 'package:daymark/models/day_override.dart';
import 'package:daymark/services/reminder_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 存储的假实现，可以模拟“永远不返回”和“直接抛错”两种坏情况。
class _FakeStore extends EventStore {
  _FakeStore([List<CountdownEvent>? events])
      : events = List.of(events ?? _defaultEvents);

  static final List<CountdownEvent> _defaultEvents = [
    CountdownEvent(
      id: 'e1',
      title: '春节',
      date: DateTime(2026, 2, 17),
      recurrence: EventRecurrence.once,
      category: '节日',
      note: '',
      reminderDays: -1,
    ),
  ];

  /// 记录列表。构造时拷贝一份：分类改名会原地替换 `events[index]`，直接持有
  /// 调用方给的那份列表，一个用例就会改到别人的数据上去。
  final List<CountdownEvent> events;
  final List<DayOverride> savedOverrides = [];
  List<String> categories = const [];
  final List<String> deleted = [];
  final List<String> updated = [];
  bool hangForever = false;
  bool failOnRead = false;

  @override
  Future<List<CountdownEvent>> allEvents() async {
    if (hangForever) {
      await Completer<void>().future;
    }
    if (failOnRead) {
      throw StateError('数据库打不开');
    }
    return events;
  }

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
  }

  @override
  Future<List<DayOverride>> allOverrides() async => List.of(savedOverrides);

  @override
  Future<void> saveOverride(DayOverride override) async {
    savedOverrides
      ..removeWhere((item) => item.origin == override.origin)
      ..add(override);
  }

  @override
  Future<void> deleteOverrides(Iterable<String> origins) async {
    savedOverrides.removeWhere((item) => origins.contains(item.origin));
  }

  @override
  Future<void> deleteEvents(Iterable<String> ids) async {
    deleted.addAll(ids);
    events.removeWhere((event) => ids.contains(event.id));
  }

  @override
  Future<void> updateEventsReminder(List<String> ids, int reminderDays) async {
    for (final event in events) {
      if (ids.contains(event.id)) updated.add('${event.id}:$reminderDays');
    }
  }

  @override
  Future<Map<String, Object?>> exportPayload() async => {
        'format': 'daymark.backup',
        'version': 1,
        'events': events.map((event) => event.toMap()).toList(),
        'overrides': savedOverrides.map((item) => item.toMap()).toList(),
        'categories': categories.isEmpty
            ? EventStore.defaultCategories
            : categories,
      };

  @override
  Future<int> importPayload(Map<String, dynamic> decoded) async {
    final rawEvents = decoded['events'];
    if (rawEvents is! List) {
      throw const FormatException('备份格式无法识别');
    }
    events
      ..clear()
      ..addAll(rawEvents.whereType<Map<String, dynamic>>().map(CountdownEvent.fromMap));
    savedOverrides
      ..clear()
      ..addAll(_overridesFrom(decoded['overrides']));
    return events.length;
  }

  static List<DayOverride> _overridesFrom(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(DayOverride.fromMap)
        .toList(growable: false);
  }

  @override
  Future<void> replaceAll(
    List<CountdownEvent> restoredEvents,
    List<DayOverride> restoredOverrides, {
    List<String>? categories,
  }) async {
    events
      ..clear()
      ..addAll(restoredEvents);
    savedOverrides
      ..clear()
      ..addAll(restoredOverrides);
    if (categories != null && categories.isNotEmpty) {
      this.categories = List.of(categories);
    }
  }

  @override
  Future<void> save(CountdownEvent event) async {}

  @override
  Future<List<String>> allCategories() async =>
      categories.isEmpty ? EventStore.defaultCategories : categories;

  @override
  Future<void> replaceCategories(List<String> names) async {
    categories = List.of(names);
  }

  @override
  Future<void> updateEventsCategory(List<String> ids, String category) async {
    for (final event in events) {
      if (ids.contains(event.id)) updated.add('${event.id}:$category');
    }
    // 真的把记录挪过去：分类改动的撤销用例要看 store 里剩下的记录，
    // 只记一条日志的话撤销后无从验证记录是否回到了原分类。
    for (final (index, event) in [...events.indexed]) {
      if (ids.contains(event.id)) {
        events[index] = event.copyWith(category: category);
      }
    }
  }

  @override
  Future<void> saveOverrides(Iterable<DayOverride> overrides) async {
    for (final override in overrides) {
      savedOverrides
        ..removeWhere((item) => item.origin == override.origin)
        ..add(override);
    }
  }
}

/// 提醒的假实现：hangForever 用来模拟通知插件通道不返回。
class _FakeReminders extends ReminderService {
  bool hangForever = false;
  bool usable = true;
  int initializeCalls = 0;

  @override
  bool get available => usable;

  @override
  Object? get lastError => usable ? null : StateError('通知插件不可用');

  @override
  Future<void> initialize() async {
    initializeCalls++;
    if (hangForever) {
      await Completer<void>().future;
    }
  }

  @override
  Future<void> cancelAll() async {}

  @override
  Future<bool> requestPermission() async => usable;

  @override
  Future<void> scheduleEvents(List<CountdownEvent> events) async {}
}

/// 离线用的假数据源：测试里绝不联网。
class _FakeHolidays extends HolidayRepository {
  _FakeHolidays() : super(endpoints: const <String>[]);

  @override
  Future<HolidaySnapshot?> loadCached() async => null;

  @override
  Future<void> cache(HolidaySnapshot snapshot) async {}

  @override
  Future<HolidaySnapshot> fetch({required int year}) async =>
      throw const HolidayUpdateException('测试环境离线');
}

CountdownEvent _event(String id, String title, {String category = '重要日'}) =>
    CountdownEvent(
      id: id,
      title: title,
      date: DateTime(2026, 6, 1),
      category: category,
    );

/// 起一个已经载入完成的控制器。分类相关的用例要反复搭同一个壳，
/// 抄一遍注入参数只会让用例本身淹没在样板里。
Future<AppController> _started(EventStore store) async {
  final controller = AppController(
    store: store,
    reminders: _FakeReminders(),
    holidays: _FakeHolidays(),
    timeout: const Duration(milliseconds: 200),
  );
  await controller.load();
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('正常启动：读取到本地数据并完成后端初始化', () async {
    final store = _FakeStore();
    final reminders = _FakeReminders();
    final controller = AppController(
      store: store,
      reminders: reminders,
      holidays: _FakeHolidays(),
      timeout: const Duration(milliseconds: 200),
    );

    await controller.load();

    expect(controller.ready, isTrue);
    expect(controller.loading, isFalse);
    expect(controller.loadError, isNull);
    expect(controller.events, hasLength(1));
    expect(reminders.initializeCalls, 1);
    controller.dispose();
  });

  test('提醒初始化卡住时依然进入主界面', () async {
    final reminders = _FakeReminders()..hangForever = true;
    final controller = AppController(
      store: _FakeStore(),
      reminders: reminders,
      holidays: _FakeHolidays(),
      timeout: const Duration(milliseconds: 200),
    );

    await controller.load();

    expect(controller.ready, isTrue);
    expect(controller.loadError, isNull);
    controller.dispose();
  });

  test('存储卡住时超时退出启动，不会永远转圈', () async {
    final store = _FakeStore()..hangForever = true;
    final controller = AppController(
      store: store,
      reminders: _FakeReminders(),
      holidays: _FakeHolidays(),
      timeout: const Duration(milliseconds: 100),
    );

    await controller.load();

    expect(controller.ready, isTrue);
    expect(controller.loadError, contains('未响应'));
    controller.dispose();
  });

  test('存储抛错时给出可展示的错误原因', () async {
    final store = _FakeStore()..failOnRead = true;
    final controller = AppController(
      store: store,
      reminders: _FakeReminders(),
      holidays: _FakeHolidays(),
      timeout: const Duration(milliseconds: 200),
    );

    await controller.load();

    expect(controller.ready, isTrue);
    expect(controller.loadError, contains('数据库打不开'));
    controller.dispose();
  });

  test('重复调用 load 不会并发叠加', () async {
    final store = _FakeStore();
    final reminders = _FakeReminders();
    final controller = AppController(
      store: store,
      reminders: reminders,
      holidays: _FakeHolidays(),
      timeout: const Duration(milliseconds: 200),
    );

    await Future.wait([controller.load(), controller.load()]);

    expect(controller.ready, isTrue);
    expect(reminders.initializeCalls, 1);
    controller.dispose();
  });

  test('批量改分类后可撤销', () async {
    final store = _FakeStore([_event('a', '生日'), _event('b', '目标')]);
    final controller = AppController(
      store: store,
      reminders: _FakeReminders(),
      holidays: _FakeHolidays(),
      timeout: const Duration(milliseconds: 200),
    );

    await controller.load();
    await controller.updateEventsCategory(['a', 'b'], '纪念日');

    expect(store.updated, containsAll(<String>['a:纪念日', 'b:纪念日']));
    expect(controller.canUndo, isTrue);
    expect(controller.undoLabel, contains('分类'));

    await controller.undo();

    expect(controller.canUndo, isFalse);
    expect(store.events, hasLength(2));
    controller.dispose();
  });

  test('恢复内置条目后可撤销改动', () async {
    final store = _FakeStore()
      ..savedOverrides.add(
        DayOverride(
          origin: 'holiday:春节:2026-02-15',
          title: '大年初一',
          date: DateTime(2026, 2, 17),
          category: '重要日',
          note: '',
          reminderDays: 0,
        ),
      );
    final controller = AppController(
      store: store,
      reminders: _FakeReminders(),
      holidays: _FakeHolidays(),
      timeout: const Duration(milliseconds: 200),
    );

    await controller.load();
    expect(controller.overrides, hasLength(1));
    expect(controller.overrideFor('holiday:春节:2026-02-15')?.title, '大年初一');

    await controller.restoreOverride('holiday:春节:2026-02-15');
    expect(controller.overrides, isEmpty);

    await controller.undo();
    expect(controller.overrideFor('holiday:春节:2026-02-15')?.title, '大年初一');
    controller.dispose();
  });

  group('分类的增删改', () {
    test('新增分类后进入清单，可撤销', () async {
      final controller = await _started(_FakeStore());
      expect(controller.categories, EventStore.defaultCategories);

      expect(await controller.addCategory('旅行'), isTrue);

      expect(controller.categories.last, '旅行');
      expect(controller.canUndo, isTrue);
      expect(controller.undoLabel, contains('旅行'));

      await controller.undo();

      expect(controller.categories, EventStore.defaultCategories);
      controller.dispose();
    });

    test('重名、空名与超长名都返回 false，不落库', () async {
      final controller = await _started(_FakeStore());

      expect(await controller.addCategory('  '), isFalse);
      expect(await controller.addCategory(List.filled(21, '长').join()), isFalse);
      // 内置清单里已经有「生日」了。
      expect(await controller.addCategory('  生日  '), isFalse);

      expect(controller.categories, EventStore.defaultCategories);
      expect(
        controller.canUndo,
        isFalse,
        reason: '什么都没改成，就不该留下一个可撤销的快照',
      );
      controller.dispose();
    });

    test('改名时挂在上面的记录跟着改，可撤销', () async {
      final store = _FakeStore([_event('a', '约定', category: '纪念日')]);
      final controller = await _started(store);

      expect(await controller.renameCategory('纪念日', '我们的日子'), isTrue);

      expect(
        controller.categories,
        [...EventStore.defaultCategories]..[0] = '我们的日子',
      );
      expect(
        (await store.allEvents()).single.category,
        '我们的日子',
        reason: '改名不搬家的话，那批记录就落在一个选不出来的分类上',
      );

      await controller.undo();

      expect(controller.categories, EventStore.defaultCategories);
      expect(
        (await store.allEvents()).single.category,
        '纪念日',
        reason: '撤销要把记录和清单一起还原',
      );
      controller.dispose();
    });

    test('删除分类时记录挪到「其他」，可撤销', () async {
      final store = _FakeStore([_event('a', '约定', category: '纪念日')]);
      final controller = await _started(store);

      expect(await controller.deleteCategory('纪念日'), isTrue);

      expect(
        controller.categories,
        EventStore.defaultCategories.where((name) => name != '纪念日'),
      );
      expect((await store.allEvents()).single.category, '其他');

      await controller.undo();

      expect(controller.categories, EventStore.defaultCategories);
      expect((await store.allEvents()).single.category, '纪念日');
      controller.dispose();
    });

    test('改名也会带着内置条目的改动记录一起改', () async {
      final store = _FakeStore()
        ..savedOverrides.add(
          DayOverride(
            origin: 'holiday:春节:2026-02-15',
            title: '春节',
            date: DateTime(2026, 2, 17),
            category: '纪念日',
            note: '',
            reminderDays: -1,
          ),
        );
      final controller = await _started(store);

      await controller.renameCategory('纪念日', '家人');

      expect(
        (await store.allOverrides()).single.category,
        '家人',
        reason: '改过的内置条目也是用户的东西，改分类名不该漏掉它',
      );
      controller.dispose();
    });

    test('「其他」不给删：它是记录挪过去的目的地', () async {
      final controller = await _started(_FakeStore());

      expect(await controller.deleteCategory('其他'), isFalse);
      expect(controller.categories, EventStore.defaultCategories);
      controller.dispose();
    });

    test('删掉清单里最后一个「其他」也不影响兜底', () async {
      final controller = await _started(_FakeStore());
      await controller.addCategory('旅行');

      expect(await controller.deleteCategory('旅行'), isTrue);

      expect(
        controller.categories,
        contains(EventStore.fallbackCategory),
        reason: '清单里没有「其他」的话，被挪过去的记录就没地方筛',
      );
      controller.dispose();
    });

    test('改名与删除都拒绝不存在的分类名', () async {
      final controller = await _started(_FakeStore());

      expect(await controller.renameCategory('不存在', '新名'), isFalse);
      expect(await controller.deleteCategory('不存在'), isFalse);
      expect(controller.categories, EventStore.defaultCategories);
      controller.dispose();
    });
  });

  test('设置会持久化，重启后仍然生效', () async {
    final controller = AppController(
      store: _FakeStore(),
      reminders: _FakeReminders(),
      holidays: _FakeHolidays(),
      timeout: const Duration(milliseconds: 200),
    );

    await controller.load();
    await controller.updateSettings(
      const AppSettings(
        themeMode: AppThemeMode.dark,
        seed: AppSeed.teal,
        remindersEnabled: true,
      ),
    );

    expect(controller.settings.themeMode, AppThemeMode.dark);
    expect(controller.remindersEnabled, isTrue);

    final restored = await SettingsStore().load();
    expect(restored.seed, AppSeed.teal);
    expect(restored.themeMode, AppThemeMode.dark);
    expect(restored.remindersEnabled, isTrue);
    controller.dispose();
  });

  test('备份导出包含设置，导入后设置跟着恢复', () async {
    final store = _FakeStore([_event('a', '生日')]);
    final controller = AppController(
      store: store,
      reminders: _FakeReminders(),
      holidays: _FakeHolidays(),
      timeout: const Duration(milliseconds: 200),
    );

    await controller.load();
    await controller.updateSettings(
      const AppSettings(seed: AppSeed.amber, useDynamicColor: true),
    );

    final json = await controller.exportJson();
    expect(json, contains('"settings"'));
    expect(json, contains('"seed": "amber"'));

    SharedPreferences.setMockInitialValues({});
    final other = AppController(
      store: _FakeStore(),
      reminders: _FakeReminders(),
      holidays: _FakeHolidays(),
      timeout: const Duration(milliseconds: 200),
    );
    await other.load();
    expect(other.settings.seed, isNot(AppSeed.amber));

    await other.importJson(json);
    expect(other.settings.seed, AppSeed.amber);
    expect(other.settings.useDynamicColor, isTrue);
    expect(other.events, hasLength(1));
    controller.dispose();
    other.dispose();
  });
}
