import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'core/calendar_engine.dart';
import 'data/backup_file_gateway.dart';
import 'data/event_store.dart';
import 'data/holiday_catalog.dart';
import 'data/holiday_repository.dart';
import 'data/settings_store.dart';
import 'models/app_settings.dart';
import 'models/countdown_event.dart';
import 'models/day_override.dart';
import 'services/reminder_service.dart';

/// 一次改动之前的数据快照，用于撤销。
class _UndoSnapshot {
  const _UndoSnapshot({
    required this.events,
    required this.overrides,
    required this.settings,
  });

  final List<CountdownEvent> events;
  final List<DayOverride> overrides;
  final AppSettings settings;
}

class AppController extends ChangeNotifier {
  AppController({
    EventStore? store,
    ReminderScheduler? reminders,
    SettingsStore? settingsStore,
    HolidayRepository? holidays,
    BackupFileGateway? backupFiles,
    this.timeout = stepTimeout,
  })  : _store = store ?? EventStore(),
        _reminders = reminders ?? ReminderService.instance,
        _settingsStore = settingsStore ?? SettingsStore(),
        _holidays = holidays ?? HolidayRepository(),
        _backupFiles = backupFiles ?? PluginBackupFileGateway();

  /// 单个启动步骤的上限。插件通道或文件系统一旦无响应，也要让界面出来，
  /// 而不是让用户对着启动转圈无限等待。
  static const Duration stepTimeout = Duration(seconds: 10);

  /// 各步骤共用的超时上限；测试里可以调小。
  final Duration timeout;

  final EventStore _store;
  final ReminderScheduler _reminders;
  final SettingsStore _settingsStore;
  final HolidayRepository _holidays;

  /// 备份文件的读写通道。剪贴板那条路不可靠——下一次复制就会冲掉备份，
  /// 换手机更是直接丢，所以正式入口走文件。
  final BackupFileGateway _backupFiles;

  List<CountdownEvent> _events = const [];
  final Map<String, DayOverride> _overrides = {};
  AppSettings _settings = const AppSettings();
  bool _ready = false;
  bool _loading = false;
  String? _loadError;
  _UndoSnapshot? _undoSnapshot;
  String _undoLabel = '';
  bool _holidayUpdating = false;
  String _holidaySource = '';
  DateTime? _holidayFetchedAt;

  List<CountdownEvent> get events => _events;

  bool get ready => _ready;
  bool get loading => _loading;

  /// 按关键词与分类过滤已加载的记录，仅供界面筛选用：既不落库也不发通知，
  /// 所以可以放心地在 build() 里直接调用。
  /// [term] 会去掉首尾空白并忽略大小写，在标题与备注里查找；为空表示不过滤。
  /// [category] 为空表示不限分类。
  List<CountdownEvent> searchResults(String term, {String? category}) {
    final keyword = term.trim().toLowerCase();
    // 空条件走快路径：不做任何判断，但仍然交出不可修改的视图，
    // 免得调用方把结果当成自己的临时列表去改。
    if (keyword.isEmpty && category == null) return List.unmodifiable(_events);
    return List<CountdownEvent>.unmodifiable([
      for (final event in _events)
        if ((category == null || event.category == category) &&
            (keyword.isEmpty ||
                event.title.toLowerCase().contains(keyword) ||
                event.note.toLowerCase().contains(keyword)))
          event,
    ]);
  }

  /// 内置条目（官方假期与传统节日）里，接下来 [days] 天内值得关注的那些。
  ///
  /// 内置数据本身不落库，每次都要现算，所以抽到状态层里给首页与搜索共用，
  /// 免得两个页面各写一份、以后改口径时只改一处。已改动（[overrides]）与已隐藏
  /// 的条目都按改动后的样子返回。
  ///
  /// 不落库也不通知，可以在 build() 里直接调用。
  List<EventOccurrence> builtInOccurrences(DateTime today, {int days = 181}) {
    final start = CalendarEngine.dateOnly(today);
    // 窗口是 [start, start + days)：传统节日交给 lunarFestivalsInRange 已经按这个
    // 口径过滤，官方假期必须自己比一次，否则会混进几百天外的假期。
    final windowEnd = start.add(Duration(days: days));
    final found = <EventOccurrence>[];

    for (final span in HolidayCatalog.spansForYear(start.year)) {
      if (span.end.isBefore(start)) continue;
      final origin = CalendarEngine.holidayOrigin(span.name, span.start);
      final patch = _overrides[origin];
      if (patch?.hidden ?? false) continue;
      // 假期已经开始时，倒数对准的是「今天」而不是假期第一天。
      // 改动后的日期也可能落到今天之前（例如把进行中的春节改到 2 月 10 日），
      // 同样要对准今天——否则界面会出现「还剩 -3 天」这种负数倒数。
      final patched = patch?.date;
      final date = patched != null && !patched.isBefore(start)
          ? patched
          : (span.start.isBefore(start) ? start : span.start);
      if (date.isAfter(windowEnd)) continue;
      found.add(
        EventOccurrence(
          title: patch?.title ?? span.name,
          date: date,
          daysRemaining: CalendarEngine.daysBetween(start, date),
          subtitle: patch == null
              ? '${HolidayCatalog.publishedYear} 官方假期'
              : '${HolidayCatalog.publishedYear} 官方假期 · 已改动',
          origin: origin,
          overridden: patch != null,
          reminderDays: patch?.reminderDays ?? -1,
        ),
      );
    }

    for (final entry
        in CalendarEngine.lunarFestivalsInRange(start, days).entries) {
      for (final name in entry.value) {
        final origin = CalendarEngine.festivalOrigin(entry.key, name);
        final patch = _overrides[origin];
        if (patch?.hidden ?? false) continue;
        final patched = patch?.date;
        // 同上：改动后的日期落到今天之前时不产生负数倒数。
        final date = patched != null && !patched.isBefore(start)
            ? patched
            : entry.key;
        found.add(
          EventOccurrence(
            title: patch?.title ?? name,
            date: date,
            daysRemaining: CalendarEngine.daysBetween(start, date),
            subtitle: patch == null ? '传统节日' : '传统节日 · 已改动',
            origin: origin,
            overridden: patch != null,
            reminderDays: patch?.reminderDays ?? -1,
          ),
        );
      }
    }

    return List<EventOccurrence>.unmodifiable(found);
  }

  /// 按关键词与分类过滤「接下来」的条目，自带记录与内置条目一起搜。
  ///
  /// 搜索框里写「春节」时，用户期待看到内置的春节假期，而不只是自己记的条目；
  /// 分类筛选对内置条目同样生效（它们默认算「重要日」，被改动过则按改动后的分类）。
  /// 返回值按剩余天数升序，与首页展示顺序一致。不落库也不通知。
  List<EventOccurrence> searchOccurrences(
    String term, {
    String? category,
    DateTime? today,
    int days = 181,
  }) {
    final start = today ?? CalendarEngine.dateOnly(DateTime.now());
    final own = searchResults(term, category: category)
        .map((event) => CalendarEngine.nextOccurrence(event, start))
        .whereType<EventOccurrence>();
    final keyword = term.trim().toLowerCase();
    // 内置条目只按标题搜，不按 subtitle 搜：subtitle 是「2026 官方假期」这类来源
    // 说明，搜「2026」会把所有官方假期一次性全列出来，搜「官方」也一样——
    // 那不是用户想找的东西。自带记录仍按标题 + 备注搜，两边口径就此不同。
    final builtIn = builtInOccurrences(start, days: days).where(
      (item) =>
          (category == null || _categoryOf(item) == category) &&
          (keyword.isEmpty || item.title.toLowerCase().contains(keyword)),
    );

    final all = <EventOccurrence>[...own, ...builtIn]
      ..sort((a, b) {
        final byDays = a.daysRemaining.compareTo(b.daysRemaining);
        return byDays != 0 ? byDays : a.title.compareTo(b.title);
      });
    return List<EventOccurrence>.unmodifiable(all);
  }

  /// 内置条目的归类：被改动过按改动的分类算，否则算「重要日」——
  /// 与 [CountdownEvent.category] 的默认值保持一致。
  String _categoryOf(EventOccurrence item) {
    final origin = item.origin;
    if (origin == null) return item.event?.category ?? '重要日';
    return _overrides[origin]?.category ?? '重要日';
  }

  /// 启动过程中失败的原因；为空表示一切正常。
  String? get loadError => _loadError;

  AppSettings get settings => _settings;
  bool get remindersEnabled => _settings.remindersEnabled;

  /// 用户对内置条目（官方节假日、传统节日）的改动，键是内置条目标识。
  Map<String, DayOverride> get overrides => Map.unmodifiable(_overrides);

  DayOverride? overrideFor(String origin) => _overrides[origin];

  /// 是否有可撤销的改动。
  bool get canUndo => _undoSnapshot != null;

  /// 上一步改动的描述，例如「删除 3 条」。
  String get undoLabel => _undoLabel;

  /// 是否正在拉取在线放假安排。
  bool get holidayUpdating => _holidayUpdating;

  /// 放假安排的数据来源与更新时间。
  String get holidaySource =>
      _holidaySource.isEmpty ? '应用内置数据' : _holidaySource;

  DateTime? get holidayFetchedAt => _holidayFetchedAt;

  bool get hasOnlineHolidays => HolidayCatalog.hasOnlineData;

  /// 需要发送提醒的条目：自己记录里开着提醒的，加上被改动后设了提醒的内置条目。
  List<CountdownEvent> get _reminderCandidates {
    final candidates = <CountdownEvent>[
      for (final event in _events)
        if (event.reminderDays >= 0) event,
    ];
    for (final override in _overrides.values) {
      if (override.reminderDays < 0 || override.hidden) continue;
      candidates.add(
        CountdownEvent(
          id: 'override:${override.origin}',
          title: override.title,
          date: override.date,
          category: override.category,
          note: override.note,
          reminderDays: override.reminderDays,
          // 时刻也要带过去，否则改了内置条目的提醒时刻不会生效。
          reminderHour: override.reminderHour,
        ),
      );
    }
    return candidates;
  }

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _loadError = null;
    notifyListeners();
    try {
      await _withTimeout(_loadCore(), '读取本地数据');
      // 提醒是可选能力，放到后台初始化：失败只降级，不阻塞界面。
      unawaited(_warmUpReminders());
      // 在线放假安排先用缓存，后台再试一次更新。
      unawaited(_applyCachedHolidays());
      unawaited(_silentHolidayRefresh());
    } catch (error, stack) {
      _loadError = _describe(error);
      debugPrint('启动载入失败：$_loadError\n$stack');
    } finally {
      // 无论成败都要结束启动状态，否则界面会永远停在转圈上。
      _ready = true;
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> reload() => load();

  Future<void> _loadCore() async {
    _settings = await _settingsStore.load();
    _events = await _store.allEvents();
    final overrides = await _store.allOverrides();
    _overrides
      ..clear()
      ..addEntries(overrides.map((item) => MapEntry(item.origin, item)));
  }

  Future<void> _warmUpReminders() async {
    try {
      await _reminders.initialize();
      if (remindersEnabled && _reminders.available) {
        await _withTimeout(
          _reminders.scheduleEvents(_reminderCandidates),
          '重建提醒',
        );
      }
    } catch (error, stack) {
      debugPrint('提醒预热失败，应用继续使用：$error\n$stack');
    }
  }

  Future<void> _applyCachedHolidays() async {
    try {
      final cached = await _holidays.loadCached();
      if (cached == null) return;
      HolidayCatalog.applyOnline(
        cached.years,
        source: cached.source,
        fetchedAt: cached.fetchedAt,
      );
      _holidaySource = cached.source;
      _holidayFetchedAt = cached.fetchedAt;
      notifyListeners();
    } catch (error) {
      debugPrint('读取节假日缓存失败：$error');
    }
  }

  /// 下拉刷新：重读本地数据，并顺手更新一次放假安排。
  Future<void> refreshAll() async {
    await _refresh();
    try {
      await refreshHolidays();
    } on Object {
      // 离线或数据源不可用时保持现有数据。
    }
  }

  /// 后台自动更新：失败就继续用现有数据，不打扰用户。
  Future<void> _silentHolidayRefresh() async {
    try {
      await refreshHolidays();
    } on Object {
      // 离线或数据源不可用时静默忽略。
    }
  }

  /// 拉取最新放假安排。失败时保持现有数据不动，并把错误抛给调用方展示。
  Future<void> refreshHolidays() async {
    if (_holidayUpdating) return;
    _holidayUpdating = true;
    notifyListeners();
    try {
      final snapshot = await _holidays.fetch(year: DateTime.now().year);
      await _holidays.cache(snapshot);
      HolidayCatalog.applyOnline(
        snapshot.years,
        source: snapshot.source,
        fetchedAt: snapshot.fetchedAt,
      );
      _holidaySource = snapshot.source;
      _holidayFetchedAt = snapshot.fetchedAt;
    } catch (error) {
      debugPrint('更新节假日数据失败：$error');
      rethrow;
    } finally {
      _holidayUpdating = false;
      notifyListeners();
    }
  }

  Future<T> _withTimeout<T>(Future<T> work, String label) => work.timeout(
        timeout,
        onTimeout: () =>
            throw TimeoutException('$label 超过 ${timeout.inSeconds} 秒未响应'),
      );

  static String _describe(Object error) {
    if (error is TimeoutException) {
      return error.message?.toString() ?? '操作超时';
    }
    return error.toString();
  }

  // ---------------------------------------------------------------- 撤销

  /// 在改动之前记录一份快照，供撤销使用。
  void _remember(String label) {
    _undoSnapshot = _UndoSnapshot(
      events: List.of(_events),
      overrides: _overrides.values.toList(growable: false),
      settings: _settings,
    );
    _undoLabel = label;
  }

  /// 撤销上一步改动。
  Future<void> undo() async {
    final snapshot = _undoSnapshot;
    if (snapshot == null) return;
    _undoSnapshot = null;
    await _withTimeout(
      _store.replaceAll(snapshot.events, snapshot.overrides),
      '撤销改动',
    );
    _events = List.of(snapshot.events);
    _overrides
      ..clear()
      ..addEntries(snapshot.overrides.map((item) => MapEntry(item.origin, item)));
    _settings = snapshot.settings;
    await _settingsStore.save(_settings);
    notifyListeners();
    await _rescheduleReminders();
  }

  // ------------------------------------------------------- 自带记录的改动

  Future<void> saveEvent(CountdownEvent event) async {
    _remember('保存「${event.title}」');
    await _withTimeout(_store.save(event), '保存记录');
    await _refresh();
  }

  Future<void> deleteEvent(String id) async {
    final title = _eventTitle(id);
    _remember('删除「$title」');
    await _withTimeout(_store.delete(id), '删除记录');
    await _refresh();
  }

  String _eventTitle(String id) =>
      _events.where((event) => event.id == id).map((event) => event.title).firstOrNull ??
      '这条记录';

  Future<void> deleteEvents(List<String> ids) async {
    if (ids.isEmpty) return;
    _remember('删除 ${ids.length} 条记录');
    await _withTimeout(_store.deleteEvents(ids), '批量删除');
    await _refresh();
  }

  Future<void> updateEventsCategory(List<String> ids, String category) async {
    if (ids.isEmpty) return;
    _remember('修改 ${ids.length} 条的分类');
    await _withTimeout(
      _store.updateEventsCategory(ids, category),
      '批量修改分类',
    );
    await _refresh();
  }

  Future<void> updateEventsReminder(List<String> ids, int reminderDays) async {
    if (ids.isEmpty) return;
    _remember('修改 ${ids.length} 条的提醒');
    await _withTimeout(
      _store.updateEventsReminder(ids, reminderDays),
      '批量修改提醒',
    );
    await _refresh();
  }

  // ------------------------------------------------------ 内置条目的改动

  Future<void> saveOverride(DayOverride override) async {
    _remember('改动「${override.title}」');
    await _withTimeout(_store.saveOverride(override), '保存改动');
    _overrides[override.origin] = override;
    notifyListeners();
    await _rescheduleReminders();
  }

  /// 取消对内置条目的改动，恢复内置数据。
  Future<void> restoreOverride(String origin) async {
    final title = _overrides[origin]?.title ?? '内置条目';
    _remember('恢复「$title」');
    await _withTimeout(_store.deleteOverrides([origin]), '恢复默认');
    _overrides.remove(origin);
    notifyListeners();
    await _rescheduleReminders();
  }

  /// 批量清除改动记录。
  Future<void> restoreOverrides(List<String> origins) async {
    if (origins.isEmpty) return;
    _remember('恢复 ${origins.length} 条内置条目');
    await _withTimeout(_store.deleteOverrides(origins), '恢复默认');
    for (final origin in origins) {
      _overrides.remove(origin);
    }
    notifyListeners();
    await _rescheduleReminders();
  }

  // ---------------------------------------------------------------- 设置

  Future<void> updateSettings(AppSettings settings) async {
    _remember('修改设置');
    _settings = settings;
    await _settingsStore.save(settings);
    notifyListeners();
    await _rescheduleReminders();
  }

  Future<bool> setRemindersEnabled(bool enabled) async {
    if (enabled && !await _reminders.requestPermission()) {
      return false;
    }
    _settings = _settings.copyWith(remindersEnabled: enabled);
    await _settingsStore.save(_settings);
    notifyListeners();
    if (enabled) {
      await _rescheduleReminders();
    } else {
      await _withTimeout(_reminders.cancelAll(), '取消提醒');
    }
    return true;
  }

  // -------------------------------------------------------- 备份与恢复

  /// 一份文件涵盖记录、内置条目改动与设置。
  Future<String> exportJson() async {
    final payload = await _store.exportPayload();
    return const JsonEncoder.withIndent('  ').convert({
      ...payload,
      'settings': _settings.toJson(),
    });
  }

  Future<int> importJson(String source) async {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('备份格式无法识别');
    }
    // 先导入再记快照：导入失败时上面的 _undoSnapshot 原封不动，用户才还撤得回
    // 上一次改动。快照此刻记下的仍是内存里的旧数据（_refresh 还没跑），也就是
    // undo() 要还原回去的那一份，所以挪到这里既安全又语义正确。
    final count = await _withTimeout(
      _store.importPayload(decoded),
      '恢复备份',
    );
    _remember('恢复备份');
    final rawSettings = decoded['settings'];
    if (rawSettings is Map<String, dynamic>) {
      _settings = AppSettings.fromJson(rawSettings);
      await _settingsStore.save(_settings);
    }
    await _refresh();
    return count;
  }

  /// 导出到文件：交给系统分享面板，由用户自己挑位置保存。
  ///
  /// 返回 `false` 表示用户在面板上点了取消，没有产生任何后果。
  /// 真正做不成时抛 [BackupFileException]，消息能直接展示。
  Future<bool> exportToFile({DateTime? now}) async {
    // exportJson 是异步的（要读一次库），所以这里必须 await，不能把 Future
    // 直接塞给网关的 String 参数。
    final content = await exportJson();
    return _withTimeout(
      _backupFiles.exportText(
        content,
        filename: backupFilename(now ?? DateTime.now()),
      ),
      '导出备份',
    );
  }

  /// 只把备份文件读出来，**不导入**。用户取消选择时返回 `null`，不当作错误。
  ///
  /// 刻意和 [importJson] 分开：导入会整份替换本机数据，必须先让用户确认，
  /// 所以界面拿到的先是文本，确认之后才调 [importJson]。
  Future<String?> readBackupFile() =>
      _withTimeout(_backupFiles.importText(), '读取备份文件');

  // ------------------------------------------------------------ 内部工具

  Future<void> _refresh() async {
    _events = await _store.allEvents();
    final overrides = await _store.allOverrides();
    _overrides
      ..clear()
      ..addEntries(overrides.map((item) => MapEntry(item.origin, item)));
    notifyListeners();
    await _rescheduleReminders();
  }

  Future<void> _rescheduleReminders() async {
    if (!remindersEnabled) return;
    try {
      if (_reminders.available) {
        await _withTimeout(
          _reminders.scheduleEvents(_reminderCandidates),
          '重建提醒',
        );
      }
    } catch (error, stack) {
      debugPrint('重建提醒失败：$error\n$stack');
    }
  }
}
