import 'dart:async';

import 'package:daymark/app_controller.dart';
import 'package:daymark/data/event_store.dart';
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
  Future<void> delete(String id) async {}

  @override
  Future<List<DayOverride>> allOverrides() async => const [];

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
}
