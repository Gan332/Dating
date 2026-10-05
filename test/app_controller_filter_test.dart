import 'dart:convert';

import 'package:daymark/app_controller.dart';
import 'package:daymark/data/event_store.dart';
import 'package:daymark/data/holiday_repository.dart';
import 'package:daymark/data/settings_store.dart';
import 'package:daymark/models/app_settings.dart';
import 'package:daymark/models/countdown_event.dart';
import 'package:daymark/models/day_override.dart';
import 'package:daymark/models/holiday_data.dart';
import 'package:daymark/services/reminder_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 内存里的存储：筛选只读控制器已加载的列表，所以统计读取次数就能证明它没碰库。
class _FakeStore extends EventStore {
  _FakeStore([List<CountdownEvent>? events])
      : events = events ?? <CountdownEvent>[];

  final List<CountdownEvent> events;
  int readCount = 0;
  bool failImport = false;

  /// 撤销时回填进来的数据，用来确认撤销恢复的正是当初那份快照。
  List<CountdownEvent>? restored;

  @override
  Future<List<CountdownEvent>> allEvents() async {
    readCount++;
    return List.of(events);
  }

  @override
  Future<List<DayOverride>> allOverrides() async => const [];

  @override
  Future<void> save(CountdownEvent event) async {
    events
      ..removeWhere((item) => item.id == event.id)
      ..add(event);
  }

  @override
  Future<void> delete(String id) async {
    events.removeWhere((item) => item.id == id);
  }

  @override
  Future<void> deleteEvents(Iterable<String> ids) async {
    events.removeWhere((item) => ids.contains(item.id));
  }

  @override
  Future<int> importPayload(Map<String, dynamic> decoded) async {
    if (failImport) throw const FormatException('备份内容不完整');
    events
      ..clear()
      ..add(const CountdownEvent(
        id: 'x',
        title: '来自文件',
        date: DateTime(2026, 1, 1),
      ));
    return 1;
  }

  @override
  Future<void> replaceAll(
    List<CountdownEvent> events,
    List<DayOverride> overrides,
  ) async {
    restored = List.of(events);
  }
}

class _FakeSettings extends SettingsStore {
  @override
  Future<AppSettings> load() async => const AppSettings();

  @override
  Future<void> save(AppSettings settings) async {}
}

class _FakeReminders implements ReminderScheduler {
  @override
  bool get available => false;

  @override
  Object? get lastError => null;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> scheduleEvents(List<CountdownEvent> events) async {}

  @override
  Future<void> cancelAll() async {}
}

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

const List<CountdownEvent> _seed = [
  CountdownEvent(
    id: 'e1',
    title: 'Anniversary',
    date: DateTime(2026, 5, 1),
    category: '纪念日',
    note: 'First Day',
  ),
  CountdownEvent(
    id: 'e2',
    title: '生日',
    date: DateTime(2026, 6, 2),
    category: '生日',
    note: 'Brother',
  ),
];

AppController _controller(_FakeStore store) => AppController(
      store: store,
      settingsStore: _FakeSettings(),
      reminders: _FakeReminders(),
      holidays: _FakeHolidays(),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('列表筛选', () {
    late _FakeStore store;
    late AppController controller;

    setUp(() async {
      store = _FakeStore(List.of(_seed));
      controller = _controller(store);
      await controller.load();
    });

    test('空条件返回全部记录', () {
      expect(controller.searchResults('').length, 2);
      expect(controller.searchResults('   ').length, 2);
      expect(controller.searchResults('', category: '生日').length, 1);
    });

    test('关键词去空白并忽略大小写', () {
      expect(controller.searchResults('  ANNIV ').map((e) => e.id), ['e1']);
    });

    test('备注同样参与匹配', () {
      expect(controller.searchResults('brother').map((e) => e.id), ['e2']);
    });

    test('关键词与分类同时生效', () {
      expect(controller.searchResults('a', category: '生日'), isEmpty);
      expect(controller.searchResults('生', category: '生日').length, 1);
    });

    test('返回的列表不可修改', () {
      expect(
        () => controller.searchResults('').add(_seed.first),
        throwsUnsupportedError,
      );
    });

    test('筛选既不读库也不发通知', () {
      final before = store.readCount;
      var notified = 0;
      controller.addListener(() => notified++);
      controller.searchResults('生日');
      controller.searchResults('x', category: '纪念日');
      expect(store.readCount, before);
      expect(notified, 0);
    });
  });

  test('导入失败时上一次的撤销快照仍然可用', () async {
    final store = _FakeStore(List.of(_seed));
    final controller = _controller(store);
    await controller.load();

    await controller.deleteEvent('e2');
    expect(controller.canUndo, isTrue);
    expect(controller.undoLabel, '删除「生日」');

    store.failImport = true;
    await expectLater(
      controller.importJson(jsonEncode({
        'format': 'daymark.backup',
        'version': 1,
        'events': [
          {'id': 'x', 'title': '来自文件', 'date': '2026-01-01'},
        ],
        'overrides': [],
      })),
      throwsA(isA<FormatException>()),
    );

    expect(controller.canUndo, isTrue);
    expect(controller.undoLabel, '删除「生日」');

    await controller.undo();
    expect(store.restored!.map((e) => e.id), ['e1', 'e2']);
  });

  test('导入成功后快照记录的是导入前的数据', () async {
    final store = _FakeStore(List.of(_seed));
    final controller = _controller(store);
    await controller.load();

    await controller.importJson(jsonEncode({
      'format': 'daymark.backup',
      'version': 1,
      'events': [
        {'id': 'x', 'title': '来自文件', 'date': '2026-01-01'},
      ],
      'overrides': [],
    }));

    expect(controller.events.single.id, 'x');
    expect(controller.canUndo, isTrue);
    await controller.undo();
    expect(store.restored!.map((e) => e.id), ['e1', 'e2']);
  });
}
