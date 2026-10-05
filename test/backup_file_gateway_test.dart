import 'dart:convert';
import 'dart:io';

import 'package:daymark/app_controller.dart';
import 'package:daymark/data/backup_file_gateway.dart';
import 'package:daymark/data/event_store.dart';
import 'package:daymark/data/holiday_repository.dart';
import 'package:daymark/models/app_settings.dart';
import 'package:daymark/models/countdown_event.dart';
import 'package:daymark/models/day_override.dart';
import 'package:daymark/models/holiday_data.dart';
import 'package:daymark/services/reminder_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 记录自己收到过什么，好断言控制器交给网关的确实是它自己生成的那一份。
class _RecordingGateway implements BackupFileGateway {
  int exportCalls = 0;
  int importCalls = 0;
  String? exportedContent;
  String? exportedFilename;

  /// 用户取消时保持为 null。
  String? importResult;

  /// 非空就让两个方法都抛出它，用来验证界面拿到的是可读的中文消息。
  Object? failure;

  @override
  Future<bool> exportText(String content, {required String filename}) async {
    exportCalls++;
    final error = failure;
    if (error != null) throw error;
    exportedContent = content;
    exportedFilename = filename;
    return true;
  }

  @override
  Future<String?> importText() async {
    importCalls++;
    final error = failure;
    if (error != null) throw error;
    return importResult;
  }
}

/// 内存里的假存储：不碰数据库，因此单测里不会有任何平台通道。
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

  @override
  Future<List<CountdownEvent>> allEvents() async => List.of(events);

  @override
  Future<List<DayOverride>> allOverrides() async => List.of(savedOverrides);

  @override
  Future<void> saveOverride(DayOverride override) async {
    savedOverrides
      ..removeWhere((item) => item.origin == override.origin)
      ..add(override);
  }

  @override
  Future<Map<String, Object?>> exportPayload() async => {
        'format': 'daymark.backup',
        'version': 2,
        'exportedAt': '2026-10-05T08:00:00.000',
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
      ..addAll(
        rawEvents.whereType<Map<String, dynamic>>().map(CountdownEvent.fromMap),
      );
    final rawOverrides = decoded['overrides'];
    savedOverrides
      ..clear()
      ..addAll(
        rawOverrides is List
            ? rawOverrides
                .whereType<Map<String, dynamic>>()
                .map(DayOverride.fromMap)
            : const <DayOverride>[],
      );
    return events.length;
  }
}

/// 提醒的假实现：备份这一段用不到通知。
class _FakeReminders extends ReminderService {
  @override
  bool get available => false;

  @override
  Object? get lastError => StateError('通知插件不可用');

  @override
  Future<void> initialize() async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Future<bool> requestPermission() async => false;

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

CountdownEvent _event(String id, String title) => CountdownEvent(
      id: id,
      title: title,
      date: DateTime(2026, 6, 1),
      category: '重要日',
    );

AppController _controller(_FakeStore store) => AppController(
      store: store,
      reminders: _FakeReminders(),
      holidays: _FakeHolidays(),
      timeout: const Duration(milliseconds: 200),
    );

/// 导出接线：控制器生成的那份 JSON 原样交给网关，文件名按导出当天算。
Future<bool> _exportThrough(
  AppController controller,
  BackupFileGateway gateway, {
  required DateTime now,
}) async {
  final json = await controller.exportJson();
  return gateway.exportText(json, filename: backupFilename(now));
}

/// 导入接线：网关读回来的文本原样交给 [AppController.importJson]；用户取消（null）
/// 就什么都不做。
Future<int?> _importThrough(
  AppController controller,
  BackupFileGateway gateway,
) async {
  final source = await gateway.importText();
  if (source == null) return null;
  return controller.importJson(source);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('备份文件名', () {
    test('月和日都补零到两位', () {
      expect(
        backupFilename(DateTime(2026, 1, 5)),
        'daymark-backup-2026-01-05.json',
      );
      expect(
        backupFilename(DateTime(2026, 9, 30)),
        'daymark-backup-2026-09-30.json',
      );
    });

    test('本来就是两位时不再补，多位数年份也不会被截断', () {
      expect(
        backupFilename(DateTime(2026, 12, 31)),
        'daymark-backup-2026-12-31.json',
      );
      expect(
        backupFilename(DateTime(1024, 3, 7)),
        'daymark-backup-1024-03-07.json',
      );
    });

    test('名字跟着传入的日期走，不缓存上一次的日期', () {
      expect(
        backupFilename(DateTime(2026, 10, 5)),
        isNot(backupFilename(DateTime(2026, 10, 6))),
      );
      expect(
        backupFilename(DateTime(2025, 12, 31)),
        isNot(backupFilename(DateTime(2026, 1, 1))),
      );
    });
  });

  group('控制器与网关之间的接缝', () {
    test('导出：网关拿到的就是控制器刚生成的那份 JSON', () async {
      final store = _FakeStore([_event('a', '生日'), _event('b', '纪念日')]);
      final controller = _controller(store);
      await controller.load();
      await controller.updateSettings(
        const AppSettings(seed: AppSeed.amber, useDynamicColor: true),
      );
      await store.saveOverride(
        DayOverride(
          origin: 'festival:春节',
          title: '春节',
          date: DateTime(2026, 2, 17),
          category: '节日',
          note: '改过名字',
          reminderDays: 0,
        ),
      );
      final gateway = _RecordingGateway();

      final finished = await _exportThrough(
        controller,
        gateway,
        now: DateTime(2026, 10, 5),
      );

      expect(finished, isTrue);
      expect(gateway.exportCalls, 1);
      expect(gateway.exportedContent, await controller.exportJson());
      expect(gateway.exportedFilename, 'daymark-backup-2026-10-05.json');
      // 备份必须是完整的一份：记录、内置条目的改动、设置都在里面，
      // 少一样，换机之后就得靠用户自己记。
      expect(gateway.exportedContent, contains('"overrides"'));
      expect(gateway.exportedContent, contains('"seed": "amber"'));
      controller.dispose();
    });

    test('导入：网关读回的文本原样恢复出记录、改动与设置', () async {
      final source = _FakeStore([_event('a', '生日'), _event('b', '纪念日')]);
      await source.saveOverride(
        DayOverride(
          origin: 'festival:春节',
          title: '春节（改）',
          date: DateTime(2026, 2, 17),
          category: '节日',
          note: '',
          reminderDays: 0,
        ),
      );
      final gateway = _RecordingGateway()
        ..importResult = const JsonEncoder.withIndent('  ').convert({
          'format': 'daymark.backup',
          'version': 2,
          'events': [
            for (final event in source.events) event.toMap(),
          ],
          'overrides': [
            for (final override in source.savedOverrides) override.toMap(),
          ],
          'settings': const AppSettings(seed: AppSeed.teal).toJson(),
        });
      final target = _FakeStore([_event('old', '旧记录')]);
      final controller = _controller(target);
      await controller.load();

      final count = await _importThrough(controller, gateway);

      expect(count, 2);
      expect(
        controller.events.map((event) => event.title),
        ['生日', '纪念日'],
      );
      expect(controller.overrides['festival:春节']?.title, '春节（改）');
      expect(controller.settings.seed, AppSeed.teal);
      expect(target.events.map((event) => event.id), ['a', 'b']);
      controller.dispose();
    });

    test('导入：用户取消时返回 null，且不碰原有数据', () async {
      final gateway = _RecordingGateway();
      final target = _FakeStore([_event('old', '旧记录')]);
      final controller = _controller(target);
      await controller.load();

      final count = await _importThrough(controller, gateway);

      expect(count, isNull);
      expect(gateway.importCalls, 1);
      expect(controller.events.map((event) => event.id), ['old']);
      expect(controller.canUndo, isFalse);
      controller.dispose();
    });

    test('网关抛出的异常原样冒泡，界面拿得到可展示的消息', () async {
      final gateway = _RecordingGateway()
        ..failure = const BackupFileException(
          '读取备份文件失败，请换一个文件试试。',
        );
      final controller = _controller(_FakeStore());
      await controller.load();

      await expectLater(
        _importThrough(controller, gateway),
        throwsA(
          isA<BackupFileException>()
              .having((e) => e.message, 'message', contains('读取备份文件失败'))
              .having((e) => e.toString(), 'toString', contains('读取备份文件失败')),
        ),
      );
      controller.dispose();
    });
  });

  group('插件实现的错误映射', () {
    late Directory tempDir;

    setUp(
      () => tempDir = Directory.systemTemp.createTempSync('daymark_backup'),
    );
    tearDown(() => tempDir.deleteSync(recursive: true));

    String writeTempFile(String name, String content) {
      final file = File('${tempDir.path}${Platform.pathSeparator}$name')
        ..writeAsStringSync(content);
      return file.path;
    }

    /// 这些用例只关心导入，分享面板一律假装成功。
    BackupShareInvoker sharedOk() =>
        (params) async => const ShareResult('', ShareResultStatus.success);

    test('导出会把原文按 UTF-8 交给分享面板，标题带上文件名', () async {
      ShareParams? captured;
      final gateway = PluginBackupFileGateway(
        share: (params) async {
          captured = params;
          return const ShareResult('', ShareResultStatus.success);
        },
        pick: () async => null,
      );
      const content = '{"format":"daymark.backup","version":2}';

      final finished = await gateway.exportText(
        content,
        filename: 'daymark-backup-2026-10-05.json',
      );

      expect(finished, isTrue);
      final files = captured!.files!;
      expect(files, hasLength(1));
      // 内容是这里唯一真正要紧的东西：用户拿到的文件必须就是这份备份原文。
      expect(utf8.decode(await files.single.readAsBytes()), content);
      // 文件名与标题由网关直接指定，钉住它们能防住有人把命名规则改掉。
      // 不去断言 XFile.name：那是 cross_file 自己的规范化行为，不是我们控制的。
      expect(captured!.title, 'daymark-backup-2026-10-05.json');
      expect(captured!.subject, '拾日备份');
    });

    test('分享面板被关掉算没完成，其余状态都算完成', () async {
      PluginBackupFileGateway gatewayWith(ShareResultStatus status) =>
          PluginBackupFileGateway(
            share: (params) async => ShareResult('', status),
            pick: () async => null,
          );

      expect(
        await gatewayWith(ShareResultStatus.dismissed)
            .exportText('{}', filename: 'a.json'),
        isFalse,
        reason: '用户主动关掉面板不该报成功',
      );
      expect(
        await gatewayWith(ShareResultStatus.unavailable)
            .exportText('{}', filename: 'a.json'),
        isTrue,
      );
      expect(
        await gatewayWith(ShareResultStatus.success)
            .exportText('{}', filename: 'a.json'),
        isTrue,
      );
    });

    test('分享面板本身出问题：抛中文异常，并带上原始错误', () async {
      final error = PlatformException(code: 'ShareFailed');
      final gateway = PluginBackupFileGateway(
        share: (params) async => throw error,
        pick: () async => null,
      );

      await expectLater(
        gateway.exportText('{}', filename: 'a.json'),
        throwsA(
          isA<BackupFileException>()
              .having((e) => e.message, 'message', '导出备份文件失败，请重试。')
              .having((e) => e.cause, 'cause', same(error))
              .having((e) => e.toString(), 'toString', '导出备份文件失败，请重试。'),
        ),
      );
    });

    test('导入：取消选择返回 null，不当成失败', () async {
      final gateway = PluginBackupFileGateway(
        share: sharedOk(),
        pick: () async => null,
      );

      expect(await gateway.importText(), isNull);
    });

    test('导入：读回的文件内容一字不改', () async {
      const content = '  {"format":"daymark.backup"}\n';
      final path = writeTempFile('backup.json', content);
      final gateway = PluginBackupFileGateway(
        share: sharedOk(),
        pick: () async => path,
      );

      expect(await gateway.importText(), content);
    });

    test('导入：只有空白字符的文件等同于取消', () async {
      final path = writeTempFile('blank.json', '\n\t  ');
      final gateway = PluginBackupFileGateway(
        share: sharedOk(),
        pick: () async => path,
      );

      expect(await gateway.importText(), isNull);
    });

    test('导入：选择器打不开时抛中文异常，并带上原始错误', () async {
      final error = PlatformException(code: 'PickFailed');
      final gateway = PluginBackupFileGateway(
        share: sharedOk(),
        pick: () async => throw error,
      );

      await expectLater(
        gateway.importText(),
        throwsA(
          isA<BackupFileException>()
              .having((e) => e.message, 'message', '打不开文件选择器，请重试。')
              .having((e) => e.cause, 'cause', same(error)),
        ),
      );
    });

    test('导入：文件读不了时抛中文异常，而不是把 IO 错误漏给界面', () async {
      final missing = '${tempDir.path}${Platform.pathSeparator}missing.json';
      final gateway = PluginBackupFileGateway(
        share: sharedOk(),
        pick: () async => missing,
      );

      await expectLater(
        gateway.importText(),
        throwsA(
          isA<BackupFileException>().having(
            (e) => e.message,
            'message',
            '读取备份文件失败，请换一个文件试试。',
          ),
        ),
      );
    });

    test('导入：选择器自己抛出的中文异常不会被二次包装', () async {
      final gateway = PluginBackupFileGateway(
        share: sharedOk(),
        pick: () async =>
            throw const BackupFileException('这个备份文件读不了，请换一个文件试试。'),
      );

      await expectLater(
        gateway.importText(),
        throwsA(
          isA<BackupFileException>().having(
            (e) => e.message,
            'message',
            '这个备份文件读不了，请换一个文件试试。',
          ),
        ),
      );
    });
  });
}
