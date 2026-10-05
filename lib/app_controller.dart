import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/event_store.dart';
import 'models/countdown_event.dart';
import 'services/reminder_service.dart';

class AppController extends ChangeNotifier {
  AppController({EventStore? store}) : _store = store ?? EventStore();

  final EventStore _store;
  List<CountdownEvent> _events = const [];
  bool _remindersEnabled = false;
  bool _ready = false;

  List<CountdownEvent> get events => _events;
  bool get remindersEnabled => _remindersEnabled;
  bool get ready => _ready;

  Future<void> load() async {
    await ReminderService.instance.initialize();
    final preferences = await SharedPreferences.getInstance();
    _remindersEnabled = preferences.getBool('remindersEnabled') ?? false;
    _events = await _store.allEvents();
    _ready = true;
    if (_remindersEnabled) {
      await ReminderService.instance.scheduleEvents(_events);
    }
    notifyListeners();
  }

  Future<void> saveEvent(CountdownEvent event) async {
    await _store.save(event);
    await _refresh();
  }

  Future<void> deleteEvent(String id) async {
    await _store.delete(id);
    await _refresh();
  }

  Future<bool> setRemindersEnabled(bool enabled) async {
    if (enabled && !await ReminderService.instance.requestPermission()) {
      return false;
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('remindersEnabled', enabled);
    _remindersEnabled = enabled;
    if (enabled) {
      await ReminderService.instance.scheduleEvents(_events);
    } else {
      await ReminderService.instance.cancelAll();
    }
    notifyListeners();
    return true;
  }

  Future<String> exportJson() => _store.exportJson();

  Future<int> importJson(String source) async {
    final count = await _store.importJson(source);
    await _refresh();
    return count;
  }

  Future<void> _refresh() async {
    _events = await _store.allEvents();
    if (_remindersEnabled) {
      await ReminderService.instance.scheduleEvents(_events);
    }
    notifyListeners();
  }
}
