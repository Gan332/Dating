import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/countdown_event.dart';
import '../models/day_override.dart';

class EventStore {
  Database? _database;

  static const int _schemaVersion = 2;

  static const String _createEvents = '''
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
        ''';

  static const String _createOverrides = '''
          CREATE TABLE day_overrides (
            origin TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            date TEXT NOT NULL,
            category TEXT NOT NULL,
            note TEXT NOT NULL,
            reminderDays INTEGER NOT NULL DEFAULT -1,
            hidden INTEGER NOT NULL DEFAULT 0
          )
        ''';

  Future<Database> get _db async {
    final current = _database;
    if (current != null) return current;
    final path = await getDatabasesPath();
    final db = await openDatabase(
      '$path/daymark_events.db',
      version: _schemaVersion,
      onCreate: (database, version) async {
        await database.execute(_createEvents);
        await database.execute(_createOverrides);
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        // 老版本没有内置条目的改动表，补建即可，已有记录不动。
        if (oldVersion < 2) {
          await database.execute(_createOverrides);
        }
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

  Future<void> deleteEvents(Iterable<String> ids) async {
    final keys = ids.toList(growable: false);
    if (keys.isEmpty) return;
    await (await _db).delete(
      'events',
      where: _inClause('id', keys.length),
      whereArgs: keys,
    );
  }

  Future<void> updateEventsCategory(List<String> ids, String category) async {
    await _updateEvents(ids, 'category', category);
  }

  Future<void> updateEventsReminder(List<String> ids, int reminderDays) async {
    await _updateEvents(ids, 'reminderDays', reminderDays);
  }

  Future<void> _updateEvents(
    List<String> ids,
    String column,
    Object value,
  ) async {
    if (ids.isEmpty) return;
    final database = await _db;
    await database.transaction((transaction) async {
      for (final id in ids) {
        await transaction.update(
          'events',
          {column: value},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    });
  }

  Future<List<DayOverride>> allOverrides() async {
    final rows = await (await _db).query('day_overrides');
    return rows.map(DayOverride.fromMap).toList(growable: false);
  }

  Future<void> saveOverride(DayOverride override) async {
    await (await _db).insert(
      'day_overrides',
      override.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveOverrides(Iterable<DayOverride> overrides) async {
    final database = await _db;
    await database.transaction((transaction) async {
      for (final override in overrides) {
        await transaction.insert(
          'day_overrides',
          override.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// 清除改动记录，内置条目回到内置状态。
  Future<void> deleteOverrides(Iterable<String> origins) async {
    final keys = origins.toList(growable: false);
    if (keys.isEmpty) return;
    await (await _db).delete(
      'day_overrides',
      where: _inClause('origin', keys.length),
      whereArgs: keys,
    );
  }

  Future<String> exportJson() async {
    final events = await allEvents();
    final overrides = await allOverrides();
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'daymark.backup',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'events': events.map((event) => event.toMap()).toList(),
      'overrides': overrides.map((override) => override.toMap()).toList(),
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

    final overrides = _readOverrides(decoded);

    final database = await _db;
    await database.transaction((transaction) async {
      await transaction.delete('events');
      for (final event in events) {
        await transaction.insert('events', event.toMap());
      }
      await transaction.delete('day_overrides');
      for (final override in overrides) {
        await transaction.insert('day_overrides', override.toMap());
      }
    });
    return events.length;
  }

  /// 备份里的改动记录；旧备份没有这个字段，按空处理。
  List<DayOverride> _readOverrides(Map<String, dynamic> decoded) {
    final raw = decoded['overrides'];
    if (raw == null) return const [];
    if (raw is! List) {
      throw const FormatException('备份中的改动记录无法识别');
    }
    if (raw.length > 2000) {
      throw const FormatException('备份中的改动记录超出限制');
    }
    return raw.map((item) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('备份中包含无效改动记录');
      }
      return DayOverride.fromMap(item);
    }).toList(growable: false);
  }

  static String _inClause(String column, int count) =>
      '$column IN (${List.filled(count, '?').join(', ')})';
}
