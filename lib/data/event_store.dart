import 'package:sqflite/sqflite.dart';

import '../models/countdown_event.dart';
import '../models/day_override.dart';

class EventStore {
  Database? _database;

  /// [databasePath] 只给测试用。应用运行期库文件固定在 `getDatabasesPath()` 下，
  /// 但 `sqflite_common_ffi` 在纯 Dart 环境里那个目录并不可用，不注入路径就没法
  /// 让单测跑真实 SQL。留空时行为与从前完全一致。
  EventStore({this.databasePath});

  final String? databasePath;

  static const int _schemaVersion = 3;

  /// 能读进来的备份版本。仍然接受 1：老备份里没有 `reminderHour`，从模型的缺省值
  /// 回落成 9 点即可，不该因为版本号旧就把用户自己的数据挡在门外。再往后的版本
  /// 字段含义未知，必须拒绝，否则可能把新结构按老结构写坏。
  static const Set<int> _readableBackupVersions = {1, 2};

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
            reminderDays INTEGER NOT NULL DEFAULT -1,
            reminderHour INTEGER NOT NULL DEFAULT 9
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
            reminderHour INTEGER NOT NULL DEFAULT 9,
            hidden INTEGER NOT NULL DEFAULT 0
          )
        ''';

  Future<Database> get _db async {
    final current = _database;
    if (current != null) return current;
    final path =
        databasePath ?? '${await getDatabasesPath()}/daymark_events.db';
    final db = await openDatabase(
      path,
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
        // 提醒时刻是后来才有的字段。给已有行补一个 9 点的默认值，
        // 免得升级后读出来的记录少一个字段、整个列表打不开。
        if (oldVersion < 3) {
          await database.execute(
            'ALTER TABLE events ADD COLUMN reminderHour INTEGER NOT NULL DEFAULT 9',
          );
          await database.execute(
            'ALTER TABLE day_overrides ADD COLUMN reminderHour INTEGER NOT NULL DEFAULT 9',
          );
        }
      },
    );
    _database = db;
    return db;
  }

  /// 关闭数据库并丢掉缓存句柄。应用运行期不调用；单测拆临时库时必须先关，
  /// 否则文件仍被占用删不掉，下一次跑会读到上次的残留数据。
  Future<void> close() async {
    final current = _database;
    _database = null;
    await current?.close();
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

  /// 备份内容。设置由控制器补进去，这样一份文件覆盖记录 + 改动 + 设置。
  Future<Map<String, Object?>> exportPayload() async {
    final events = await allEvents();
    final overrides = await allOverrides();
    return {
      'format': 'daymark.backup',
      'version': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'events': events.map((event) => event.toMap()).toList(),
      'overrides': overrides.map((override) => override.toMap()).toList(),
    };
  }

  /// 全量替换，用于撤销上一步改动。
  Future<void> replaceAll(
    List<CountdownEvent> events,
    List<DayOverride> overrides,
  ) async {
    final database = await _db;
    await database.transaction((transaction) async {
      await transaction.delete('events');
      await transaction.delete('day_overrides');
      for (final event in events) {
        await transaction.insert('events', event.toMap());
      }
      for (final override in overrides) {
        await transaction.insert('day_overrides', override.toMap());
      }
    });
  }

  /// 导入一份备份，返回事件条数。
  Future<int> importPayload(Map<String, dynamic> decoded) async {
    final version = decoded['version'];
    if (decoded['format'] != 'daymark.backup' ||
        (version is! num ||
            !_readableBackupVersions.contains(version.toInt())) ||
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
