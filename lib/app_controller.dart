import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/event_store.dart';
import 'models/countdown_event.dart';
import 'models/day_override.dart';
import 'services/reminder_service.dart';

class AppController extends ChangeNotifier {
  AppController({
    EventStore? store,
    ReminderScheduler? reminders,
    this.timeout = stepTimeout,
  })  : _store = store ?? EventStore(),
        _reminders = reminders ?? ReminderService.instance;

  /// 单个启动步骤的上限。插件通道或文件系统一旦无响应，也要让界面出来，
  /// 而不是让用户对着启动转圈无限等待。
  static const Duration stepTimeout = Duration(seconds: 10);

  /// 各步骤共用的超时上限；测试里可以调小。
  final Duration timeout;

  final EventStore _store;
  final ReminderScheduler _reminders;

  List<CountdownEvent> _events = const [];
  final Map<String, DayOverride> _overrides = {};
  bool _remindersEnabled = false;
  bool _ready = false;
  bool _loading = false;
  String? _loadError;

  List<CountdownEvent> get events => _events;
  bool get remindersEnabled => _remindersEnabled;
  bool get ready => _ready;
  bool get loading => _loading;

  /// 启动过程中失败的原因；为空表示一切正常。
  String? get loadError => _loadError;

  /// 用户对内置条目（官方节假日、传统节日）的改动，键是内置条目标识。
  Map<String, DayOverride> get overrides => Map.unmodifiable(_overrides);

  DayOverride? overrideFor(String origin) => _overrides[origin];

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
    final preferences = await SharedPreferences.getInstance();
    _remindersEnabled = preferences.getBool('remindersEnabled') ?? false;
    _events = await _store.allEvents();
    final overrides = await _store.allOverrides();
    _overrides
      ..clear()
      ..addEntries(overrides.map((item) => MapEntry(item.origin, item)));
  }

  Future<void> _warmUpReminders() async {
    try {
      await _reminders.initialize();
      if (_remindersEnabled && _reminders.available) {
        await _withTimeout(
          _reminders.scheduleEvents(_reminderCandidates),
          '重建提醒',
        );
      }
    } catch (error, stack) {
      debugPrint('提醒预热失败，应用继续使用：$error\n$stack');
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

  Future<void> saveEvent(CountdownEvent event) async {
    await _withTimeout(_store.save(event), '保存记录');
    await _refresh();
  }

  Future<void> deleteEvent(String id) async {
    await _withTimeout(_store.delete(id), '删除记录');
    await _refresh();
  }

  Future<bool> setRemindersEnabled(bool enabled) async {
    if (enabled && !await _reminders.requestPermission()) {
      return false;
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('remindersEnabled', enabled);
    _remindersEnabled = enabled;
    if (enabled) {
      await _withTimeout(
        _reminders.scheduleEvents(_reminderCandidates),
        '安排提醒',
      );
    } else {
      await _withTimeout(_reminders.cancelAll(), '取消提醒');
    }
    notifyListeners();
    return true;
  }

  Future<String> exportJson() => _store.exportJson();

  Future<int> importJson(String source) async {
    final count = await _withTimeout(_store.importJson(source), '恢复备份');
    await _refresh();
    return count;
  }

  Future<void> _refresh() async {
    _events = await _store.allEvents();
    if (_remindersEnabled) {
      await _withTimeout(
        _reminders.scheduleEvents(_reminderCandidates),
        '重建提醒',
      );
    }
    notifyListeners();
  }

  /// 保存对内置条目的改动。
  Future<void> saveOverride(DayOverride override) async {
    await _withTimeout(_store.saveOverride(override), '保存改动');
    _overrides[override.origin] = override;
    notifyListeners();
    await _syncOverrideReminders();
  }

  /// 取消对内置条目的改动，恢复内置数据。
  Future<void> restoreOverride(String origin) async {
    await _withTimeout(_store.deleteOverrides([origin]), '恢复默认');
    _overrides.remove(origin);
    notifyListeners();
    await _syncOverrideReminders();
  }

  /// 批量清除改动记录。
  Future<void> restoreOverrides(List<String> origins) async {
    if (origins.isEmpty) return;
    await _withTimeout(_store.deleteOverrides(origins), '恢复默认');
    for (final origin in origins) {
      _overrides.remove(origin);
    }
    notifyListeners();
    await _syncOverrideReminders();
  }

  Future<void> _syncOverrideReminders() async {
    if (!_remindersEnabled) return;
    try {
      await _withTimeout(
        _reminders.scheduleEvents(_reminderCandidates),
        '重建提醒',
      );
    } catch (error, stack) {
      debugPrint('改动后重建提醒失败：$error\n$stack');
    }
  }
}
