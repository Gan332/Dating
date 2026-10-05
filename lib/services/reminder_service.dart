import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import '../core/calendar_engine.dart';
import '../models/countdown_event.dart';

class ReminderService {
  ReminderService._();

  static final ReminderService instance = ReminderService._();
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    timezone_data.initializeTimeZones();
    timezone.setLocalLocation(timezone.getLocation('Asia/Shanghai'));
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_notification'),
    );
    await _plugin.initialize(settings: settings);
  }

  Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final result = await android?.requestNotificationsPermission();
    return result ?? true;
  }

  Future<void> cancelAll() => _plugin.cancelAll();

  Future<void> scheduleEvents(List<CountdownEvent> events) async {
    await _plugin.cancelAll();
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
  }

  int _notificationId(String value, int occurrenceIndex) {
    var hash = 0;
    for (final code in value.codeUnits) {
      hash = (hash * 31 + code) & 0x3fffffff;
    }
    return ((hash * 2) + occurrenceIndex) & 0x7fffffff;
  }
}
