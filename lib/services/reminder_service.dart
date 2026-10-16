import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
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

  /// 系统是否已经允许精确提醒。
  ///
  /// 单纯的状态查询：拿不到就返回 false，提醒照常安排、只是可能晚一些，所以既
  /// 不拦任何操作，也不许抛异常（与「可选能力不抛错」的约定一致）。
  Future<bool> canScheduleExactly();

  /// 跳到系统的「闹钟和提醒」授权页；返回是否已经拿到权限。
  Future<bool> requestExactAlarmsPermission();
}

/// 一条记录的某次发生，应该在什么时刻提醒；不需要提醒或时刻已经过了返回 null。
///
/// 纯函数：只做算术，不碰插件也不读时钟（[now] 由调用方给），测试能钉死结果。
DateTime? reminderTrigger(
  CountdownEvent event,
  DateTime occurrence,
  DateTime now,
) {
  if (event.reminderDays < 0) return null;
  final day = CalendarEngine.dateOnly(occurrence);
  // 用「日期 + 天数」构造而不是 subtract(Duration(days: n))：跨夏令时切换时
  // 加减 24 小时的整数倍会漂到前一天 23 点，日期构造不会。
  final trigger = DateTime(
    day.year,
    day.month,
    day.day - event.reminderDays,
    event.reminderHour,
  );
  return trigger.isAfter(now) ? trigger : null;
}

/// 通知 id：同一条记录的不同次发生要错开，重建提醒时又要稳定不变。
int notificationId(String eventId, int occurrenceIndex) {
  var hash = 0;
  for (final code in eventId.codeUnits) {
    hash = (hash * 31 + code) & 0x3fffffff;
  }
  return ((hash * 2) + occurrenceIndex) & 0x7fffffff;
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

  /// 取不到设备时区时的落点。东八区是这个应用的主要用户群，但设备真在别处时
  /// 会以设备为准（见 [_deviceLocation]）。
  static const String fallbackTimeZone = 'Asia/Shanghai';

  @override
  bool get available => _available;

  @override
  Object? get lastError => _lastError;

  @override
  Future<void> initialize() => _initializing ??= _initializeOnce();

  Future<void> _initializeOnce() async {
    try {
      timezone_data.initializeTimeZones();
      timezone.setLocalLocation(await _deviceLocation());
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

  /// 设备当前所在的时区。
  ///
  /// 每次排提醒前都重新查一次，不能只在 [initialize] 里定一次：`_initializing ??=`
  /// 保证初始化只跑一遍，用户旅行或手动改时区之后就会一直按旧时区算，把「早上
  /// 9 点」算成别的时间。名字不认识（个别 ROM 会返回怪名字）就退回东八区。
  Future<timezone.Location> _deviceLocation() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone().timeout(
        channelTimeout,
      );
      return timezone.getLocation(info.identifier);
    } catch (error) {
      debugPrint('取设备时区失败，改用 $fallbackTimeZone：$error');
      return timezone.getLocation(fallbackTimeZone);
    }
  }

  /// 保证通知可用；不可用时返回 false，让调用方安静地跳过提醒。
  Future<bool> _ensureAvailable() async {
    await initialize();
    return _available;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<bool> requestPermission() async {
    if (!await _ensureAvailable()) return false;
    try {
      final result = await _android?.requestNotificationsPermission();
      return result ?? true;
    } catch (error) {
      debugPrint('请求通知权限失败：$error');
      return false;
    }
  }

  @override
  Future<bool> canScheduleExactly() async {
    if (!await _ensureAvailable()) return false;
    try {
      // 平台没实现或系统版本太老时返回 null，一律当成「不能」，
      // 于是排提醒走不精确那条路，而不是抛出去把整轮调度打断。
      final exact = await _android?.canScheduleExactNotifications();
      return exact ?? false;
    } catch (error) {
      debugPrint('查询精确提醒权限失败：$error');
      return false;
    }
  }

  @override
  Future<bool> requestExactAlarmsPermission() async {
    if (!await _ensureAvailable()) return false;
    try {
      final granted = await _android?.requestExactAlarmsPermission();
      return granted ?? false;
    } catch (error) {
      debugPrint('请求精确提醒权限失败：$error');
      return false;
    }
  }

  @override
  Future<void> scheduleEvents(List<CountdownEvent> events) async {
    if (!await _ensureAvailable()) return;
    try {
      await _plugin.cancelAll().timeout(channelTimeout);
      final now = DateTime.now();
      // 时区与「能不能准时」每次调度各查一次：用户可能刚换过时区，
      // 也可能刚在系统设置里允许了精确提醒。
      final zone = await _deviceLocation();
      final scheduleMode = await canScheduleExactly()
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
      for (final event in events) {
        if (event.reminderDays < 0) continue;
        final dates = CalendarEngine.occurrences(event, now, limit: 2);
        for (var index = 0; index < dates.length; index++) {
          final trigger = reminderTrigger(event, dates[index], now);
          if (trigger == null) continue;
          await _plugin.zonedSchedule(
            id: notificationId(event.id, index),
            title: event.title,
            body: event.reminderDays == 0
                ? '今天是${event.title}'
                : '距${event.title}还有${event.reminderDays}天',
            scheduledDate: timezone.TZDateTime.from(trigger, zone),
            notificationDetails: const NotificationDetails(
              android: AndroidNotificationDetails(
                'daymark_reminders',
                '纪念日提醒',
                channelDescription: '重要日期的本地提醒',
                importance: Importance.defaultImportance,
                priority: Priority.defaultPriority,
              ),
            ),
            androidScheduleMode: scheduleMode,
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
}
