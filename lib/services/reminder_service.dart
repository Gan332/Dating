import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import '../core/calendar_engine.dart';
import '../models/countdown_event.dart';

/// 控制器只依赖这个接口，测试时可以替换成假的实现。
///
/// 约定：任何实现都不能把异常抛给调用方。提醒是可选项，初始化失败只应
/// 降级为「不提醒」，绝不能让应用卡在启动画面上。
abstract class ReminderScheduler {
  /// 初始化通知插件；重复调用共享同一次初始化。
  Future<void> initialize();

  /// 通知功能当前是否可用。
  bool get available;

  /// 不可用时的原因，便于在界面上说明。
  Object? get lastError;

  Future<bool> requestPermission();

  Future<void> scheduleEvents(List<CountdownEvent> events);

  Future<void> cancelAll();
}

class ReminderService implements ReminderScheduler {
  ReminderService();

  static final ReminderService instance = ReminderService();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void>? _initializing;
  bool _available = false;
  Object? _lastError;

  /// 通知插件通道无响应时的兜底上限。
  static const Duration channelTimeout = Duration(seconds: 10);

  @override
  bool get available => _available;

  @override
  Object? get lastError => _lastError;

  @override
  Future<void> initialize() => _initializing ??= _initializeOnce();

  Future<void> _initializeOnce() async {
    try {
      timezone_data.initializeTimeZones();
      timezone.setLocalLocation(timezone.getLocation('Asia/Shanghai'));
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      );
      await _plugin
          .initialize(settings: settings)
          .timeout(channelTimeout);
      _available = true;
    } catch (error, stack) {
      _available = false;
      _lastError = error;
      debugPrint('提醒服务初始化失败，已降级为不发送提醒：$error\n$stack');
    }
  }

  /// 保证通知可用；不可用时返回 false，让调用方安静地跳过提醒。
  Future<bool> _ensureAvailable() async {
    await initialize();
    return _available;
  }

  @override
  Future<bool> requestPermission() async {
    if (!await _ensureAvailable()) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final result = await android?.requestNotificationsPermission();
      return result ?? true;
    } catch (error) {
      debugPrint('请求通知权限失败：$error');
      return false;
    }
  }

  @override
  Future<void> scheduleEvents(List<CountdownEvent> events) async {
    if (!await _ensureAvailable()) return;
    try {
      await _plugin.cancelAll().timeout(channelTimeout);
      final now = DateTime.now();
      for (final event in events) {
        if (event.reminderDays < 0) continue;
        final dates = CalendarEngine.occurrences(event, now, limit: 2);
        for (var index = 0; index < dates.length; index++) {
          final date = dates[index].subtract(Duration(days: event.reminderDays));
          final trigger = DateTime(date.year, date.month, date.day, 9);
          if (!trigger.isAfter(now)) continue;
          final notificationId = _notificationId(event.id, index);
          await _plugin.zonedSchedule(
            id: notificationId,
            title: event.title,
            body: event.reminderDays == 0
                ? '今天是${event.title}'
                : '距${event.title}还有${event.reminderDays}天',
            scheduledDate: timezone.TZDateTime.from(trigger, timezone.local),
            notificationDetails: const NotificationDetails(
              android: AndroidNotificationDetails(
                'daymark_reminders',
                '纪念日提醒',
                channelDescription: '重要日期的本地提醒',
                importance: Importance.defaultImportance,
                priority: Priority.defaultPriority,
              ),
            ),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            payload: event.id,
          );
        }
      }
    } catch (error, stack) {
      debugPrint('安排本地提醒失败：$error\n$stack');
    }
  }

  @override
  Future<void> cancelAll() async {
    if (!await _ensureAvailable()) return;
    try {
      await _plugin.cancelAll().timeout(channelTimeout);
    } catch (error) {
      debugPrint('取消本地提醒失败：$error');
    }
  }

  int _notificationId(String value, int occurrenceIndex) {
    var hash = 0;
    for (final code in value.codeUnits) {
      hash = (hash * 31 + code) & 0x3fffffff;
    }
    return ((hash * 2) + occurrenceIndex) & 0x7fffffff;
  }
}
