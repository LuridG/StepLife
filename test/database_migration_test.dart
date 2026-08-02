import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:steplife/core/db/database_service.dart';

/// v8 数据库 fixture（与历史 onCreate 一致，不含新列）
Future<Database> _createV8Database(String path) async {
  final db = await databaseFactory.openDatabase(path, options: OpenDatabaseOptions(
    version: 8,
    onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE user_profile (
          id INTEGER PRIMARY KEY DEFAULT 1,
          heightCm REAL, weightKg REAL, gender TEXT, age INTEGER,
          customStrideCm REAL, preferredViewMode TEXT DEFAULT 'card'
        )
      ''');
      await db.execute('''
        CREATE TABLE routes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL, description TEXT,
          measuredBy TEXT NOT NULL DEFAULT '自己',
          refSteps INTEGER DEFAULT 2000, isLocked INTEGER DEFAULT 0,
          createdAt TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE step_logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          routeId INTEGER, routeName TEXT NOT NULL,
          walkerName TEXT NOT NULL DEFAULT '自己',
          timesCount INTEGER NOT NULL DEFAULT 1,
          steps INTEGER NOT NULL, durationMinutes INTEGER NOT NULL,
          distanceKm REAL NOT NULL, caloriesKcal REAL NOT NULL,
          timestamp TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE members (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL, gender TEXT DEFAULT '男',
          heightCm REAL DEFAULT 170.0, weightKg REAL DEFAULT 65.0,
          age INTEGER DEFAULT 25, customStrideCm REAL,
          avatarIcon TEXT, colorValue INTEGER
        )
      ''');
      await db.execute('''
        CREATE TABLE chore_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL, category TEXT, iconName TEXT,
          isQuantifiable INTEGER DEFAULT 0, unit TEXT DEFAULT '次'
        )
      ''');
      await db.execute('''
        CREATE TABLE chore_logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          choreId INTEGER NOT NULL, choreTitle TEXT NOT NULL,
          memberIdsJson TEXT NOT NULL, memberNamesJson TEXT NOT NULL,
          memo TEXT, value REAL, timestamp TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE store_categories (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE, iconName TEXT DEFAULT 'storefront'
        )
      ''');
      await db.execute('''
        CREATE TABLE store_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL, category TEXT NOT NULL,
          rating REAL NOT NULL DEFAULT 5.0, imagesJson TEXT NOT NULL,
          address TEXT, notes TEXT, createdAt TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE store_logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          storeId INTEGER NOT NULL, storeName TEXT NOT NULL,
          cost REAL,
          visitorIdsJson TEXT NOT NULL DEFAULT '[]',
          visitorNamesJson TEXT NOT NULL DEFAULT '[]',
          memo TEXT, timestamp TEXT NOT NULL
        )
      ''');
      // 种子数据
      await db.insert('user_profile', {'id': 1, 'preferredViewMode': 'list'});
      await db.insert('members', {'name': '成员A', 'gender': '男', 'age': 28});
      await db.insert('routes', {
        'name': '测试路线', 'measuredBy': '自己', 'refSteps': 2000,
        'createdAt': DateTime.now().toIso8601String(),
      });
      await db.insert('step_logs', {
        'routeId': 1, 'routeName': '测试路线', 'steps': 5000,
        'durationMinutes': 30, 'distanceKm': 3.2, 'caloriesKcal': 150.0,
        'timestamp': DateTime.now().toIso8601String(),
      });
      await db.insert('chore_items', {'title': '扫地', 'category': '日常家务'});
      await db.insert('chore_logs', {
        'choreId': 1, 'choreTitle': '扫地', 'memberIdsJson': '[1]',
        'memberNamesJson': '["成员A"]', 'value': 1.0,
        'timestamp': DateTime.now().toIso8601String(),
      });
      await db.insert('store_categories', {'name': '影视剧集', 'iconName': 'movie'});
      await db.insert('store_categories', {'name': '餐饮美食', 'iconName': 'restaurant'});
      await db.insert('store_categories', {'name': '我的自定义', 'iconName': 'dashboard'});
      await db.insert('store_items', {
        'name': '流浪地球2', 'category': '影视剧集', 'rating': 4.9,
        'imagesJson': '[]', 'address': '万达影城',
        'createdAt': DateTime.now().toIso8601String(),
      });
      await db.insert('store_items', {
        'name': '川湘阁', 'category': '餐饮美食', 'rating': 4.8,
        'imagesJson': '[]', 'address': '中山路',
        'createdAt': DateTime.now().toIso8601String(),
      });
      await db.insert('store_logs', {
        'storeId': 1, 'storeName': '流浪地球2', 'cost': 90.0,
        'visitorIdsJson': '[1]', 'visitorNamesJson': '["成员A"]',
        'memo': '震撼', 'timestamp': DateTime.now().toIso8601String(),
      });
    },
  ));
  return db;
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('steplife_migration_');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('v8 → v9 迁移：行数不变、模板绑定正确、偏好已迁移、留痕写入', () async {
    final dbPath = p.join(tempDir.path, 'steplife_v8.db');
    final db8 = await _createV8Database(dbPath);
    await db8.close();

    // 模拟新版应用打开（version 9 + 非破坏迁移）
    final db9 = await databaseFactory.openDatabase(dbPath, options: OpenDatabaseOptions(
      version: 9,
      onUpgrade: (db, oldVersion, newVersion) async {
        await DatabaseService.instance.migrateV8ToV9(db);
      },
    ));

    // 行数对账（与迁移前一致）
    expect((await db9.rawQuery('SELECT COUNT(*) AS c FROM store_categories')).first['c'], 3);
    expect((await db9.rawQuery('SELECT COUNT(*) AS c FROM store_items')).first['c'], 2);
    expect((await db9.rawQuery('SELECT COUNT(*) AS c FROM store_logs')).first['c'], 1);
    expect((await db9.rawQuery('SELECT COUNT(*) AS c FROM members')).first['c'], 1);
    expect((await db9.rawQuery('SELECT COUNT(*) AS c FROM step_logs')).first['c'], 1);
    expect((await db9.rawQuery('SELECT COUNT(*) AS c FROM chore_logs')).first['c'], 1);

    // 模板智能绑定：影视剧集→movie、餐饮美食→dining、自定义→generic
    final cats = await db9.query('store_categories', orderBy: 'id ASC');
    expect(cats[0]['templateKey'], 'movie');
    expect(cats[1]['templateKey'], 'dining');
    expect(cats[2]['templateKey'], 'generic');

    // 新列默认值
    final items = await db9.query('store_items');
    for (final item in items) {
      expect(item['extrasJson'], '{}');
    }
    final logs = await db9.query('store_logs');
    for (final log in logs) {
      expect(log['extrasJson'], '{}');
    }

    // 偏好迁移：app_settings 有值且旧字段保留
    final pref = await db9.query('app_settings', where: "key = 'preferredViewMode'");
    expect(pref, isNotEmpty);
    expect(pref.first['value'], 'list');
    final legacy = await db9.query('user_profile', columns: ['preferredViewMode']);
    expect(legacy.first['preferredViewMode'], 'list');

    // 迁移留痕
    final trace = await db9.query('app_settings', where: "key = 'last_schema_migration'");
    expect(trace, isNotEmpty);
    expect((trace.first['value'] as String).contains('v8_to_v9:'), isTrue);

    // 完整性
    final integrity = await db9.rawQuery('PRAGMA integrity_check');
    expect(integrity.first.values.first, 'ok');

    await db9.close();
  });

  test('v8 → v9 迁移幂等：重复执行不产生重复数据', () async {
    final dbPath = p.join(tempDir.path, 'steplife_v8.db');
    final db8 = await _createV8Database(dbPath);
    await db8.close();

    final db9 = await databaseFactory.openDatabase(dbPath, options: OpenDatabaseOptions(
      version: 9,
      onUpgrade: (db, oldVersion, newVersion) async {
        await DatabaseService.instance.migrateV8ToV9(db);
      },
    ));
    // 再次手动执行迁移（模拟重复触发），应抛出或幂等不报错
    await DatabaseService.instance.migrateV8ToV9(db9);
    expect((await db9.rawQuery('SELECT COUNT(*) AS c FROM store_items')).first['c'], 2);
    final traces = await db9.query('app_settings', where: "key = 'last_schema_migration'");
    expect(traces.length, 1);
    await db9.close();
  });
}
