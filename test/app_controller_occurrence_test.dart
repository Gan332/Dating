import 'dart:convert';

import 'package:daymark/app_controller.dart';
import 'package:daymark/core/calendar_engine.dart';
import 'package:daymark/data/backup_file_gateway.dart';
import 'package:daymark/data/event_store.dart';
import 'package:daymark/data/holiday_catalog.dart';
import 'package:daymark/data/holiday_repository.dart';
import 'package:daymark/data/settings_store.dart';
import 'package:daymark/models/app_settings.dart';
import 'package:daymark/models/countdown_event.dart';
import 'package:daymark/models/day_override.dart';
import 'package:daymark/models/holiday_data.dart';
import 'package:daymark/services/reminder_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 假期已经开始的那天：用它验证「倒数十天」不会因为区间已开始而变成负数。
final DateTime _insideSpringFestival = DateTime(2026, 2, 18);

/// 春节假期开始前的那天：内置条目都还没到点。
final DateTime _beforeSpringFestival = DateTime(2026, 2, 10);

/// 国庆假期前、且不在任何已公布区间里的那天。
final DateTime _beforeNationalDay = DateTime(2026, 9, 20);

String _originOf(HolidaySpan span) =>
    CalendarEngine.holidayOrigin(span.name, span.start);

HolidaySpan _span(String name) => HolidayCatalog.spansForYear(2026)
    .firstWhere((span) => span.name == name, orElse: () {
      throw StateError('内置安排里没有「$name」');
    });

EventOccurrence? _byOrigin(List<EventOccurrence> items, String origin) {
  for (final item in items) {
    if (item.origin == origin) return item;
  }
  return null;
}

/// 内存里的存储：改动要能活过一次重新载入，所以改动记录也得存得住。
class _FakeStore extends EventStore {
  _FakeStore([List<CountdownEvent>? events])
      : events = events ?? <CountdownEvent>[];

  final List<CountdownEvent> events;
  final List<DayOverride> savedOverrides = [];

  @override
  Future<List<CountdownEvent>> allEvents() async => List.of(events);

  @override
  Future<List<DayOverride>> allOverrides() async => List.of(savedOverrides);

  @override
  Future<void> save(CountdownEvent event) async {
    events
      ..removeWhere((item) => item.id == event.id)
      ..add(event);
  }

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

  @override
  Future<void> replaceAll(
    List<CountdownEvent> events,
    List<DayOverride> overrides,
  ) async {}
}

/// 记录自己收到过什么，好断言控制器交给网关的确实是它自己生成的那一份。
class _RecordingGateway implements BackupFileGateway {
  String? exportedContent;
  String? exportedFilename;

  /// 用户在分享面板上点了取消时网关交回的值。
  bool exportResult = true;

  /// 为 null 表示用户在文件选择器上直接取消。
  String? importResult;

  /// 非空就让两个方法都抛出它。
  Object? failure;

  @override
  Future<bool> exportText(String content, {required String filename}) async {
    final error = failure;
    if (error != null) throw error;
    exportedContent = content;
    exportedFilename = filename;
    return exportResult;
  }

  @override
  Future<String?> importText() async {
    final error = failure;
    if (error != null) throw error;
    return importResult;
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

CountdownEvent _event(String id, String title, DateTime date) => CountdownEvent(
      id: id,
      title: title,
      date: date,
    );

AppController _controller(
  _FakeStore store, [
  BackupFileGateway? backupFiles,
]) =>
    AppController(
      store: store,
      settingsStore: _FakeSettings(),
      reminders: _FakeReminders(),
      holidays: _FakeHolidays(),
      backupFiles: backupFiles,
      timeout: const Duration(milliseconds: 200),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // 内置安排存在静态覆盖层里：测试之间必须清干净，否则这个文件里写进去的
  // 线上数据会漏给后面的用例。
  tearDown(HolidayCatalog.clearOnline);

  group('内置条目', () {
    late _FakeStore store;
    late AppController controller;

    setUp(() async {
      store = _FakeStore();
      controller = _controller(store);
      await controller.load();
    });

    test('还没开始的假期按公布的起始日倒数', () {
      final item = _byOrigin(
        controller.builtInOccurrences(_beforeSpringFestival),
        _originOf(_span('春节')),
      );

      expect(item, isNotNull);
      expect(item!.title, '春节');
      expect(item.date, DateTime(2026, 2, 15));
      expect(item.daysRemaining, 5);
      expect(item.event, isNull);
      expect(item.editable, isTrue);
      expect(item.overridden, isFalse);
    });

    test('假期已经开始时倒数十天是零，而不是第一天或负数', () {
      final origin = _originOf(_span('春节'));
      final item = _byOrigin(
        controller.builtInOccurrences(_insideSpringFestival),
        origin,
      );

      expect(item, isNotNull);
      expect(item!.date, _insideSpringFestival);
      expect(item.daysRemaining, 0);
      expect(item.title, '春节');
    });

    test('窗口只装得下眼前这几天时，窗口外的假期不进列表', () {
      // 2026-02-10 起只看 30 天：春节（02-15）装得下，端午（06-19）装不下。
      final origins = controller
          .builtInOccurrences(_beforeSpringFestival, days: 30)
          .map((item) => item.origin)
          .toSet();

      expect(origins, contains(_originOf(_span('春节'))));
      expect(origins, isNot(contains(_originOf(_span('端午节')))));
      // 端午在 158 天后，明确证明它确实落在窗口之外而不是恰好被跳过。
      expect(
        _span('端午节').start.difference(_beforeSpringFestival).inDays,
        greaterThan(30),
      );
    });

    test('把进行中的假期改到今天之前，倒数也是零而不是负数', () async {
      final origin = _originOf(_span('春节'));
      // 春节区间 02-15..02-23 尚未结束，但用户把日期改到了 02-10（今天之前）。
      await store.saveOverride(
        DayOverride(
          origin: origin,
          title: '春节',
          date: DateTime(2026, 2, 10),
          category: '重要日',
          note: '',
          reminderDays: -1,
        ),
      );
      await controller.load();

      final item = _byOrigin(
        controller.builtInOccurrences(_insideSpringFestival),
        origin,
      );

      expect(item, isNotNull);
      expect(item!.date, _insideSpringFestival);
      expect(item.daysRemaining, 0);
    });

    test('已经完全过去的假期不再出现在列表里', () {
      final origins = controller
          .builtInOccurrences(_insideSpringFestival)
          .map((item) => item.origin)
          .toList();

      expect(origins, isNot(contains(_originOf(_span('元旦')))));
      // 同一个列表里还没过去的假期仍然在。
      expect(origins, contains(_originOf(_span('国庆节'))));
    });

    test('改名之后内置条目按改动后的名字出现，并标记为已改动', () async {
      final origin = _originOf(_span('春节'));

      await controller.saveOverride(
        DayOverride(
          origin: origin,
          title: '大年初一',
          date: DateTime(2026, 2, 15),
          category: '节日',
          note: '回老家',
          reminderDays: 0,
        ),
      );
      await controller.reload();

      final item =
          _byOrigin(controller.builtInOccurrences(_beforeSpringFestival), origin);

      expect(item, isNotNull);
      expect(item!.title, '大年初一');
      expect(item.overridden, isTrue);
      expect(item.daysRemaining, 5);
      expect(item.reminderDays, 0);
      expect(item.subtitle, contains('已改动'));
    });

    test('改期之后倒数日跟着新日期走', () async {
      final origin = _originOf(_span('春节'));

      await controller.saveOverride(
        DayOverride(
          origin: origin,
          title: '春节',
          date: DateTime(2026, 2, 20),
          category: '重要日',
          note: '',
          reminderDays: -1,
        ),
      );

      final item =
          _byOrigin(controller.builtInOccurrences(_beforeSpringFestival), origin);
      expect(item!.date, DateTime(2026, 2, 20));
      expect(item.daysRemaining, 10);
    });

    test('隐藏之后这条内置条目彻底不见，搜索里也搜不到', () async {
      final origin = _originOf(_span('国庆节'));

      await controller.saveOverride(
        DayOverride(
          origin: origin,
          title: '国庆节',
          date: DateTime(2026, 10, 1),
          category: '重要日',
          note: '',
          reminderDays: -1,
          hidden: true,
        ),
      );
      await controller.reload();

      final builtIn = controller.builtInOccurrences(_beforeNationalDay);
      expect(builtIn.map((item) => item.origin), isNot(contains(origin)));
      // 同一批里别的内置条目不受影响。
      expect(builtIn.map((item) => item.origin), contains(_originOf(_span('中秋节'))));

      final found = controller.searchOccurrences('国庆节', today: _beforeNationalDay);
      expect(
        found.map((item) => item.origin),
        everyElement(isNot(origin)),
      );
    });

    test('取消改动之后内置条目回到公布的样子', () async {
      final origin = _originOf(_span('中秋节'));

      await controller.saveOverride(
        DayOverride(
          origin: origin,
          title: '改过的中秋',
          date: DateTime(2026, 9, 25),
          category: '重要日',
          note: '',
          reminderDays: -1,
        ),
      );
      await controller.restoreOverride(origin);

      final item =
          _byOrigin(controller.builtInOccurrences(_beforeNationalDay), origin);
      expect(item!.title, '中秋节');
      expect(item.overridden, isFalse);
    });

    test('算出来的列表不可修改', () {
      expect(
        () => controller.builtInOccurrences(_beforeSpringFestival).clear(),
        throwsUnsupportedError,
      );
    });
  });

  group('条目搜索', () {
    late _FakeStore store;
    late AppController controller;

    setUp(() async {
      store = _FakeStore([
        _event('e1', '发薪日', DateTime(2026, 2, 12)),
        _event('e2', '体检', DateTime(2026, 2, 20)),
        CountdownEvent(
          id: 'e3',
          title: '妈妈生日',
          date: DateTime(2026, 12, 3),
          category: '生日',
          note: '记得买蛋糕',
        ),
      ]);
      controller = _controller(store);
      await controller.load();
    });

    test('搜假期名字能搜到内置条目，它不是用户自己的记录', () {
      final origin = _originOf(_span('春节'));

      final found = controller.searchOccurrences('春节', today: _beforeSpringFestival);

      final item = _byOrigin(found, origin);
      expect(item, isNotNull);
      expect(item!.title, '春节');
      expect(item.event, isNull);
      expect(item.origin, isNotNull);
      expect(item.editable, isTrue);
      // 内置条目只出现在内置数据里，不会凭空多出用户记录。
      expect(found.where((row) => row.origin == null), isEmpty);
    });

    test('标题里的关键词能搜到自己的记录，备注里的也一样', () {
      final byTitle =
          controller.searchOccurrences('发薪', today: _beforeSpringFestival);
      expect(byTitle.map((item) => item.event?.id), ['e1']);

      final byNote =
          controller.searchOccurrences('蛋糕', today: _beforeSpringFestival);
      expect(byNote.map((item) => item.event?.id), ['e3']);
      expect(byNote.single.origin, isNull);
      expect(byNote.single.subtitle, '生日');
    });

    test('搜不到时返回空列表，而不是退回全部条目', () {
      expect(
        controller.searchOccurrences('不存在的关键词', today: _beforeSpringFestival),
        isEmpty,
      );
    });

    test('搜来源说明里的词不会把所有假期都列出来', () {
      // 内置条目的 subtitle 是「2026 官方假期」这类来源说明，不是用户写的内容。
      // 若拿它参与匹配，搜「2026」会把当年所有官方假期一次性全列出来。
      expect(
        controller.searchOccurrences('2026', today: _beforeNationalDay),
        isEmpty,
      );
      expect(
        controller.searchOccurrences('官方假期', today: _beforeNationalDay),
        isEmpty,
      );
      // 但按假期名字搜依然要能搜到。
      expect(
        controller
            .searchOccurrences('国庆节', today: _beforeNationalDay)
            .where((item) => item.origin != null),
        isNotEmpty,
      );
    });

    test('分类筛选对内置条目同样生效，没改动的算重要日', () {
      final origin = _originOf(_span('国庆节'));

      final important =
          controller.searchOccurrences('国庆节', category: '重要日', today: _beforeNationalDay);
      expect(
        important.map((item) => item.origin),
        contains(origin),
      );

      final birthday =
          controller.searchOccurrences('国庆节', category: '生日', today: _beforeNationalDay);
      expect(
        birthday.map((item) => item.origin),
        isNot(contains(origin)),
      );
    });

    test('被改动过的内置条目按改动后的分类参与筛选', () async {
      final origin = _originOf(_span('国庆节'));
      await controller.saveOverride(
        DayOverride(
          origin: origin,
          title: '国庆节',
          date: DateTime(2026, 10, 1),
          category: '纪念日',
          note: '',
          reminderDays: -1,
        ),
      );

      final anniversary = controller
          .searchOccurrences('国庆节', category: '纪念日', today: _beforeNationalDay);
      expect(
        anniversary.map((item) => item.origin),
        contains(origin),
      );

      final important = controller
          .searchOccurrences('国庆节', category: '重要日', today: _beforeNationalDay);
      expect(
        important.map((item) => item.origin),
        isNot(contains(origin)),
      );
    });

    test('结果按剩余天数从少到多排，自己记的与内置的混在一起', () {
      final found = controller.searchOccurrences('', today: _beforeSpringFestival);
      final days = found.map((item) => item.daysRemaining).toList();

      for (var i = 1; i < days.length; i++) {
        expect(days[i], greaterThanOrEqualTo(days[i - 1]), reason: '第 $i 项排错了');
      }

      int indexOf(bool Function(EventOccurrence) match) =>
          found.indexWhere(match);

      expect(
        indexOf((item) => item.event?.id == 'e1'),
        lessThan(indexOf((item) => item.origin == _originOf(_span('春节')))),
        reason: '2 天后的发薪日应该排在 5 天后的春节前面',
      );
      expect(
        indexOf((item) => item.event?.id == 'e1'),
        lessThan(indexOf((item) => item.event?.id == 'e2')),
      );
    });

    test('空条件返回全部条目，空白关键词与不筛分类同样如此', () {
      final everything =
          controller.searchOccurrences('', today: _beforeSpringFestival);

      expect(
        everything.length,
        3 + controller.builtInOccurrences(_beforeSpringFestival).length,
      );
      expect(
        controller.searchOccurrences('   ', today: _beforeSpringFestival).map((i) => i.title),
        everything.map((i) => i.title),
      );
      // 只给分类也是「不筛关键词」，不该把结果清空。
      expect(
        controller
            .searchOccurrences('', category: '生日', today: _beforeSpringFestival)
            .map((item) => item.event?.id),
        ['e3'],
      );
    });

    test('算出来的列表不可修改', () {
      expect(
        () => controller.searchOccurrences('', today: _beforeSpringFestival).clear(),
        throwsUnsupportedError,
      );
    });
  });

  group('备份文件', () {
    late _RecordingGateway gateway;

    setUp(() {
      gateway = _RecordingGateway();
    });

    test('导出的文件内容是一份完整备份，文件名按导出那天补零', () async {
      final store = _FakeStore([
        _event('e1', '妈妈生日', DateTime(2026, 12, 3)),
        _event('e2', '体检', DateTime(2027, 1, 8)),
      ]);
      await store.saveOverride(
        DayOverride(
          origin: 'holiday:中秋节:2026-09-25',
          title: '中秋节',
          date: DateTime(2026, 9, 25),
          category: '重要日',
          note: '',
          reminderDays: 1,
        ),
      );
      final controller = _controller(store, gateway);
      await controller.load();

      final finished = await controller.exportToFile(now: DateTime(2026, 1, 5));

      expect(finished, isTrue);
      expect(gateway.exportedFilename, 'daymark-backup-2026-01-05.json');

      final decoded = jsonDecode(gateway.exportedContent!) as Map<String, dynamic>;
      expect(decoded['format'], 'daymark.backup');
      expect(
        (decoded['events'] as List)
            .cast<Map<String, dynamic>>()
            .map((event) => event['title']),
        ['妈妈生日', '体检'],
      );
      expect(
        (decoded['overrides'] as List)
            .cast<Map<String, dynamic>>()
            .map((item) => item['origin']),
        ['holiday:中秋节:2026-09-25'],
      );
      expect(decoded['settings'], isA<Map<String, dynamic>>());
    });

    test('文件名跟着传入的日期走，不会退回读当天', () async {
      final controller = _controller(_FakeStore(), gateway);
      await controller.load();

      await controller.exportToFile(now: DateTime(2026, 11, 9));
      expect(gateway.exportedFilename, 'daymark-backup-2026-11-09.json');

      await controller.exportToFile(now: DateTime(2025, 3, 7));
      expect(gateway.exportedFilename, 'daymark-backup-2025-03-07.json');
    });

    test('用户在分享面板上取消时导出返回未完成', () async {
      gateway.exportResult = false;
      final controller = _controller(_FakeStore([_event('e1', '体检', DateTime(2027, 1, 8))]), gateway);
      await controller.load();

      expect(await controller.exportToFile(now: DateTime(2026, 1, 5)), isFalse);
    });

    test('从文件恢复之后记录与改动都换成备份里的内容', () async {
      final source = _FakeStore([_event('a', '妈妈生日', DateTime(2026, 12, 3))]);
      await source.saveOverride(
        DayOverride(
          origin: 'holiday:国庆节:2026-10-01',
          title: '国庆长假',
          date: DateTime(2026, 10, 1),
          category: '纪念日',
          note: '',
          reminderDays: 3,
        ),
      );
      gateway.importResult = const JsonEncoder.withIndent('  ').convert({
        'format': 'daymark.backup',
        'version': 2,
        'events': [
          for (final event in source.events) event.toMap(),
        ],
        'overrides': [
          for (final override in source.savedOverrides) override.toMap(),
        ],
        'settings': const AppSettings().toJson(),
      });
      final store = _FakeStore([_event('old', '旧记录', DateTime(2026, 3, 3))]);
      final controller = _controller(store, gateway);
      await controller.load();

      // 读文件本身不导入：界面要先拿文本让用户确认，确认之后才调 importJson。
      final backupText = await controller.readBackupFile();
      expect(backupText, isNotNull);
      expect(controller.events.map((event) => event.id), ['old']);

      final count = await controller.importJson(backupText!);

      expect(count, 1);
      expect(controller.events.map((event) => event.id), ['a']);
      expect(controller.events.single.title, '妈妈生日');
      expect(controller.overrides['holiday:国庆节:2026-10-01']?.title, '国庆长假');
    });

    test('用户取消选择文件时不当作失败，也不碰已有数据', () async {
      final store = _FakeStore([_event('old', '旧记录', DateTime(2026, 3, 3))]);
      final controller = _controller(store, gateway);
      await controller.load();

      expect(await controller.readBackupFile(), isNull);
      expect(controller.events.map((event) => event.id), ['old']);
      expect(controller.canUndo, isFalse);
    });

    test('读不到备份文件时把可展示的中文错误原样抛出', () async {
      gateway.failure = const BackupFileException('读取备份文件失败，请换一个文件试试。');
      final controller = _controller(_FakeStore([_event('old', '旧记录', DateTime(2026, 3, 3))]), gateway);
      await controller.load();

      await expectLater(
        controller.readBackupFile(),
        throwsA(
          isA<BackupFileException>().having(
            (e) => e.message,
            'message',
            '读取备份文件失败，请换一个文件试试。',
          ),
        ),
      );
      expect(controller.events.map((event) => event.id), ['old']);
    });
  });
}