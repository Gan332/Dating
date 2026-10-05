import 'dart:async';

import 'package:daymark/app_controller.dart';
import 'package:daymark/data/event_store.dart';
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
      : events = events ??
            [
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

  final List<CountdownEvent> events;
  final List<DayOverride> savedOverrides = [];
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
  Future<void> updateEventsCategory(List<String> ids, String category) async {
    for (final event in events) {
      if (ids.contains(event.id)) updated.add('${event.id}:$category');
    }
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
      };

  @override
  Future<int> importPayload(Map<String, dynamic> decoded) async {
    final rawEvents = decoded['events'];
    if (rawEvents is! List) {
      throw const FormatException('备份格式无法识别');
    }
    events
      ..clear()
      ..addAll(rawEvents.map(CountdownEvent.fromMap));
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
    List<DayOverride> restoredOverrides,
  ) async {
    events
      ..clear()
      ..addAll(restoredEvents);
    savedOverrides
      ..clear()
      ..addAll(restoredOverrides);
  }

  @override
  Future<int> importJson(String source) async => 0;

  @override
  Future<String> exportJson() async => '{}';

  @override
  Future<void> save(CountdownEvent event) async {}
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

CountdownEvent _event(String id, String title, {String category = '重要日'}) =>
    CountdownEvent(
      id: id,
      title: title,
      date: DateTime(2026, 6, 1),
      category: category,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('正常启动：读取到本地数据并完成后端初始化', () async {
    final store = _FakeStore();
    final reminders = _FakeReminders();
    final controller = AppController(
      store: store,
      reminders: reminders,
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

  test('设置会持久化，重启后仍然生效', () async {
    final controller = AppController(
      store: _FakeStore(),
      reminders: _FakeReminders(),
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
      timeout: const Duration(milliseconds: 200),
    );

    await controller.load();
    await controller.updateSettings(
      const AppSettings(seed: AppSeed.amber, useDynamicColor: true),
    );

    final json = await controller.exportJson();
    expect(json, contains('"settings"'));
    expect(json, contains('"seed": "amber"'));

    final other = AppController(
      store: _FakeStore(),
      reminders: _FakeReminders(),
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
