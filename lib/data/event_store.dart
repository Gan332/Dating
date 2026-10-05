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

  static const int _schemaVersion = 4;

  /// 能读进来的备份版本。
  ///
  /// 1：没有 `reminderHour`，从模型缺省值回落成 9 点。
  /// 2：加了 `reminderHour`。
  /// 3：加了 `createdAt` 与 `coverPath`，并第一次带上用户自定义的分类清单。
  /// 1 和 2 都只是缺字段，从模型的缺省值回落即可，不该因为版本号旧就把用户自己的
  /// 数据挡在门外；分类清单同理，缺失时从记录里现有的分类推导。
  /// 再往后的版本字段含义未知，必须拒绝，否则可能把新结构按老结构写坏。
  static const Set<int> _readableBackupVersions = {1, 2, 3};

  /// 备份信封版本。与 [_readableBackupVersions] 分开：写出的永远是最新版本，
  /// 读的时候才需要照顾旧的。
  static const int backupVersion = 3;

  /// 分类清单的上限，与备份导入的校验保持一致。
  static const int maxCategories = 50;

  /// 分类名的长度上限。够写「结婚纪念日」这类短名，也不至于让筛选条挤爆。
  static const int maxCategoryLength = 20;

  /// 内置的默认分类。新装时按这个顺序建表，老用户升级时用它兜底补齐——
  /// 用户的记录里可能引用了任何名字，但编辑器只该给出这几个起步选项。
  ///
  /// 直接引用模型层那份常量，不另抄一遍：清单只有这一处权威，改名时不会漏。
  static const List<String> defaultCategories = kEventCategories;

  /// 删掉某个分类时，挂在它上面的记录改到这里。不能直接删干净，否则那些记录会
  /// 变成一个界面上再也选不出来的分类，用户只能看到分类名却没法筛选它。
  static const String fallbackCategory = '其他';

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
            reminderHour INTEGER NOT NULL DEFAULT 9,
            createdAt INTEGER NOT NULL DEFAULT 0,
            coverPath TEXT
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
            hidden INTEGER NOT NULL DEFAULT 0,
            coverPath TEXT
          )
        ''';

  /// 分类清单。顺序由 sortOrder 决定，用户拖动或增删后重写整张表。
  static const String _createCategories = '''
          CREATE TABLE categories (
            name TEXT PRIMARY KEY,
            sortOrder INTEGER NOT NULL
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
        await database.execute(_createCategories);
        await _seedDefaultCategories(database);
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
        // 排序与封面：createdAt 给已有行补 0（含义是「不知道什么时候建的」，
        // 在按创建时间排序时排最后），coverPath 可空所以不用给默认值。
        if (oldVersion < 4) {
          await database.execute(
            'ALTER TABLE events ADD COLUMN createdAt INTEGER NOT NULL DEFAULT 0',
          );
          await database.execute('ALTER TABLE events ADD COLUMN coverPath TEXT');
          await database.execute(
            'ALTER TABLE day_overrides ADD COLUMN coverPath TEXT',
          );
          await database.execute(_createCategories);
          await _seedDefaultCategories(database);
        }
      },
    );
    _database = db;
    return db;
  }

  /// 新建库或升级后的第一件事：把内置分类按顺序写进去。
  ///
  /// 只在用户还没有任何自定义分类时写（表是刚建的，本来就是空的）；
  /// 迁移老库时先收集记录里已经在用的分类名，避免把用户正在用的名字挤掉。
  static Future<void> _seedDefaultCategories(Database database) async {
    final existing = await database.query('categories');
    if (existing.isNotEmpty) return;

    // 老记录里可能已经用了别的分类名（早于自定义分类功能时也是可能的），
    // 这些名字必须留在清单里，否则用户就再也筛不出那批记录了。
    final inUse = <String>{
      ...await _categoriesInUse(database, 'events'),
      ...await _categoriesInUse(database, 'day_overrides'),
    };
    final names = <String>[
      ...inUse.where((name) => !defaultCategories.contains(name)),
      ...defaultCategories,
    ];
    await _writeCategories(database, names);
  }

  static Future<List<String>> _categoriesInUse(
    DatabaseExecutor database,
    String table,
  ) async {
    final rows = await database.rawQuery(
      'SELECT DISTINCT category FROM $table ORDER BY category',
    );
    return rows
        .map((row) => row['category'] as String? ?? '')
        .where((name) => name.trim().isNotEmpty)
        .toList(growable: false);
  }

  /// 整表替换分类清单。调用方负责去重与上限校验（见 [readCategoriesFromBackup]
  /// 与控制器），这里只负责落库。
  static Future<void> _writeCategories(
    DatabaseExecutor database,
    List<String> names,
  ) async {
    for (var index = 0; index < names.length; index++) {
      await database.insert('categories', {
        'name': names[index],
        'sortOrder': index,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
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

  /// 保存一条记录。[event] 带 createdAt 为 0 时按「新建」处理，补上当前时刻。
  ///
  /// 补在存储层而不是编辑器里，是因为备份导入、撤销回滚都会走 [replaceAll]，
  /// 那两条路径不会经过编辑器；把「0 意味着未知」这件事收在这里，
  /// 每一处落库拿到的都是同一个约定。
  Future<void> save(CountdownEvent event) async {
    final stored = event.createdAt == 0
        ? event.copyWith(createdAt: DateTime.now().millisecondsSinceEpoch)
        : event;
    await (await _db).insert(
      'events',
      stored.toMap(),
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

  /// 分类清单，按用户排定的顺序返回。
  ///
  /// 库表理论上不会是空的（建表时就写进了内置分类），但万一读到空表，
  /// 这里补回 [defaultCategories] 兜底——界面上的筛选条绝不能空空如也。
  Future<List<String>> allCategories() async {
    final rows = await (await _db).query(
      'categories',
      orderBy: 'sortOrder ASC',
    );
    final names = rows
        .map((row) => row['name'] as String? ?? '')
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    return names.isEmpty ? defaultCategories : names;
  }

  /// 整表替换分类清单。
  ///
  /// 不在这里做删除迁移：删分类的语义（「挂在上面的记录改到『其他』」）是界面
  /// 决策，由控制器在同一笔改动里先改记录再改清单，才能一起撤销。
  Future<void> replaceCategories(List<String> names) async {
    if (names.isEmpty) return;
    final database = await _db;
    await database.transaction((transaction) async {
      await transaction.delete('categories');
      await _writeCategories(transaction, names);
    });
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
    final categories = await allCategories();
    return {
      'format': 'daymark.backup',
      'version': backupVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'events': events.map((event) => event.toMap()).toList(),
      'overrides': overrides.map((override) => override.toMap()).toList(),
      'categories': categories,
    };
  }

  /// 全量替换，用于撤销上一步改动。
  ///
  /// [categories] 为空时保持本机现有的分类清单不动：分类尚未被改动过的情况下，
  /// 撤销一条记录不该顺带把分类表也清掉。
  Future<void> replaceAll(
    List<CountdownEvent> events,
    List<DayOverride> overrides, {
    List<String>? categories,
  }) async {
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
      if (categories != null && categories.isNotEmpty) {
        await transaction.delete('categories');
        await _writeCategories(transaction, categories);
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
    // 分类清单的校验放在开事务之前：被拒时本机的三张表都不该被动过。
    final categories = readCategoriesFromBackup(decoded, events, overrides);
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
      await transaction.delete('categories');
      await _writeCategories(transaction, categories);
    });
    return events.length;
  }

  /// 从备份里取出分类清单，缺失时按记录里实际用到的分类推导。
  ///
  /// 版本 1 与 2 的备份没有这个字段，但那时用户已经在给记录分类了。这些名字必须
  /// 一个不落地保留下来，否则导入之后界面上的筛选条会漏掉用户真正在用的分类，
  /// 那些记录看上去像是「没有分类」。
  ///
  /// 校验与其他字段一致：不是数组、数量超限、有空名或超长名、有重名，一律拒绝整份
  /// 备份——半份清单比没有清单更难解释。
  static List<String> readCategoriesFromBackup(
    Map<String, dynamic> decoded,
    List<CountdownEvent> events,
    List<DayOverride> overrides,
  ) {
    final raw = decoded['categories'];
    if (raw == null) {
      // 老备份：内置分类原样带上（用户还得能给新记录选它们），再把记录里已经在用的、
      // 但不属于内置的那些名字补在后面——那些是用户当年自己起的分类名，
      // 漏掉的话导入后那批记录看上去就像「没有分类」。
      final inUse = <String>{
        for (final event in events) event.category,
        for (final override in overrides) override.category,
      }.where((name) => name.trim().isNotEmpty);
      final extra = inUse
          .where((name) => !defaultCategories.contains(name))
          .toList(growable: false);
      return [...defaultCategories, ...extra];
    }
    if (raw is! List) {
      throw const FormatException('备份中的分类清单无法识别');
    }
    if (raw.length > maxCategories) {
      throw const FormatException('备份中的分类数量超出限制');
    }
    final names = <String>[];
    final seen = <String>{};
    for (final item in raw) {
      if (item is! String) {
        throw const FormatException('备份中包含无效分类');
      }
      final name = item.trim();
      if (name.isEmpty) {
        throw const FormatException('备份中包含空分类名');
      }
      if (name.length > maxCategoryLength) {
        throw const FormatException('备份中的分类名过长');
      }
      // 按名字去重：同一份备份里出现两个「生日」时界面只会显示一个，
      // 与其静悄悄地合并，不如当作格式有问题拒绝掉。
      if (!seen.add(name)) {
        throw const FormatException('备份中包含重复分类名');
      }
      names.add(name);
    }
    // 全删光的清单会让用户没法给新记录分类，补回内置分类兜底。
    return names.isEmpty ? defaultCategories : names;
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
