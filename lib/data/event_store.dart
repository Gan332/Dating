import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/countdown_event.dart';

class EventStore {
  Database? _database;

  Future<Database> get _db async {
    final current = _database;
    if (current != null) return current;
    final path = await getDatabasesPath();
    final db = await openDatabase(
      '$path/daymark_events.db',
      version: 1,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE events (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            date TEXT NOT NULL,
            recurrence TEXT NOT NULL,
            category TEXT NOT NULL,
            note TEXT NOT NULL,
            lunarMonth INTEGER,
            lunarDay INTEGER,
            reminderDays INTEGER NOT NULL DEFAULT -1
          )
        ''');
      },
    );
    _database = db;
    return db;
  }

  Future<List<CountdownEvent>> allEvents() async {
    final rows = await (await _db).query('events', orderBy: 'date ASC');
    return rows.map(CountdownEvent.fromMap).toList(growable: false);
  }

  Future<void> save(CountdownEvent event) async {
    await (await _db).insert(
      'events',
      event.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String id) async {
    await (await _db).delete('events', where: 'id = ?', whereArgs: [id]);
  }

  Future<String> exportJson() async {
    final events = await allEvents();
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'daymark.backup',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'events': events.map((event) => event.toMap()).toList(),
    });
  }

  Future<int> importJson(String source) async {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != 'daymark.backup' ||
        decoded['version'] != 1 ||
        decoded['events'] is! List) {
      throw const FormatException('备份格式无法识别');
    }
    final rawEvents = decoded['events'] as List;
    if (rawEvents.length > 1000) {
      throw const FormatException('备份中的事件数量超出限制');
    }
    final events = rawEvents.map((raw) {
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('备份中包含无效事件');
      }
      final event = CountdownEvent.fromMap(raw);
      if (event.title.trim().isEmpty || event.title.length > 80) {
        throw const FormatException('备份中包含无效标题');
      }
      return event;
    }).toList(growable: false);
    if (events.map((event) => event.id).toSet().length != events.length) {
      throw const FormatException('备份中包含重复事件');
    }

    final database = await _db;
    await database.transaction((transaction) async {
      await transaction.delete('events');
      for (final event in events) {
        await transaction.insert('events', event.toMap());
      }
    });
    return events.length;
  }
}
