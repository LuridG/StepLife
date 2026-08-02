import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:steplife/core/db/database_service.dart';

/// 历史缺陷修复回归测试：
/// 旧版曾以“全新库”方式创建 v9（未迁移 v8），本测试验证 v8 数据接管合并：
/// 成员出生日期回填、分类模板按名称重绑定、打卡日志去重合并、迁移留痕写入。
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  Future<void> createV8(String path) async {
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
            avatarIcon TEXT, colorValue INTEGER,
            birthDate TEXT
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
        await db.insert('members', {'name': '成员A', 'birthDate': '1998-01-28', 'gender': '男', 'age': 28});
        await db.insert('routes', {'name': '测试路线', 'measuredBy': '自己', 'refSteps': 2000, 'createdAt': '2026-07-01T08:00:00'});
        await db.insert('chore_items', {'title': '扫地', 'category': '日常家务'});
        await db.insert('chore_logs', {
          'choreId': 1, 'choreTitle': '扫地', 'memberIdsJson': '[1]',
          'memberNamesJson': '["成员A"]', 'memo': 'v8原始备注',
          'timestamp': '2026-07-26T15:55:00',
        });
        await db.insert('store_categories', {'name': '影视剧集', 'iconName': 'movie'});
        await db.insert('store_categories', {'name': '餐饮美食', 'iconName': 'restaurant'});
        await db.insert('store_items', {
          'name': '流浪地球2', 'category': '影视剧集', 'rating': 4.9,
          'imagesJson': '[]', 'address': '万达影城', 'createdAt': '2026-07-01T08:00:00',
        });
        await db.insert('store_logs', {
          'storeId': 1, 'storeName': '流浪地球2', 'cost': 90.0,
          'visitorIdsJson': '[1]', 'visitorNamesJson': '["成员A"]',
          'memo': '影院双人观影', 'timestamp': '2026-07-28T12:20:27',
        });
      },
    ));
    await db.close();
  }

  /// 模拟旧版缺陷创建的全新 v9：种子分类全部 generic、无迁移留痕、成员出生日期为空
  Future<void> createBrokenV9(String path) async {
    final db = await databaseFactory.openDatabase(path, options: OpenDatabaseOptions(
      version: 9,
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
            name TEXT NOT NULL UNIQUE, iconName TEXT DEFAULT 'storefront',
            templateKey TEXT NOT NULL DEFAULT 'generic',
            extraFieldsJson TEXT NOT NULL DEFAULT '[]'
          )
        ''');
        await db.execute('''
          CREATE TABLE store_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL, category TEXT NOT NULL,
            rating REAL NOT NULL DEFAULT 5.0, imagesJson TEXT NOT NULL,
            address TEXT, notes TEXT, createdAt TEXT NOT NULL,
            extrasJson TEXT NOT NULL DEFAULT '{}'
          )
        ''');
        await db.execute('''
          CREATE TABLE store_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            storeId INTEGER NOT NULL, storeName TEXT NOT NULL,
            cost REAL,
            visitorIdsJson TEXT NOT NULL DEFAULT '[]',
            visitorNamesJson TEXT NOT NULL DEFAULT '[]',
            memo TEXT, timestamp TEXT NOT NULL,
            extrasJson TEXT NOT NULL DEFAULT '{}'
          )
        ''');
        await db.execute('CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT)');
        await db.insert('members', {'name': '成员A', 'gender': '男', 'age': 28});
        await db.insert('members', {'name': '成员B', 'gender': '女', 'age': 26});
        await db.insert('members', {'name': '成员C', 'gender': '男', 'age': 14});
        await db.insert('routes', {'name': '测试路线', 'measuredBy': '自己', 'refSteps': 2000, 'createdAt': '2026-08-01T08:00:00'});
        await db.insert('chore_items', {'title': '扫地', 'category': '日常家务'});
        // 用户在 v9 里新增的打卡（v8 无此行）
        await db.insert('chore_logs', {
          'choreId': 1, 'choreTitle': '扫地', 'memberIdsJson': '[1,2,3]',
          'memberNamesJson': '["成员A","成员B","成员C"]', 'memo': '',
          'timestamp': '2026-08-02T20:47:00',
        });
        await db.insert('step_logs', {
          'routeId': 1, 'routeName': '测试路线', 'walkerName': '自己',
          'steps': 2500, 'durationMinutes': 30, 'distanceKm': 1.7,
          'caloriesKcal': 113.0, 'timestamp': '2026-08-02T20:47:57',
        });
        await db.insert('store_categories', {'name': '影视剧集', 'iconName': 'movie'});
        await db.insert('store_categories', {'name': '餐饮美食', 'iconName': 'restaurant'});
        await db.insert('store_items', {
          'name': '流浪地球2', 'category': '影视剧集', 'rating': 4.9,
          'imagesJson': '[]', 'address': '万达影城', 'createdAt': '2026-08-01T08:00:00',
        });
        // 种子副本：时间戳与 v8 不同
        await db.insert('store_logs', {
          'storeId': 1, 'storeName': '流浪地球2', 'cost': 90.0,
          'visitorIdsJson': '[1]', 'visitorNamesJson': '["成员A"]',
          'memo': '影院双人观影', 'timestamp': '2026-07-31T20:44:08',
        });
      },
    ));
    await db.close();
  }

  test('v8 接管合并：回填出生日期、重绑定模板、日志去重合并、写入留痕', () async {
    final tempDir = await Directory.systemTemp.createTemp('legacy_import_');
    await createV8(p.join(tempDir.path, 'steplife_v8.db'));
    await createBrokenV9(p.join(tempDir.path, 'steplife_v9.db'));
    databaseFactory.setDatabasesPath(tempDir.path);

    final db = await DatabaseService.instance.database;

    // 成员：v9 已有 A/B/C，A 的出生日期从 v8 回填
    final members = await db.query('members', orderBy: 'id ASC');
    expect(members.length, 3);
    expect(members.first['name'], '成员A');
    expect(members.first['birthDate'], '1998-01-28');

    // 分类：从 generic 重绑定为正确模板
    final cats = await db.query('store_categories', orderBy: 'id ASC');
    final catMap = {for (final c in cats) c['name']: c['templateKey']};
    expect(catMap['影视剧集'], 'movie');
    expect(catMap['餐饮美食'], 'dining');

    // 打卡日志：v8 与 v9 的 chore_log 均保留（2 条）；step_log 保留 v9 的 1 条
    final choreLogs = await db.query('chore_logs');
    expect(choreLogs.length, 2);
    final stepLogs = await db.query('step_logs');
    expect(stepLogs.length, 1);

    // store_logs：语义去重为 1 条，并回填 v8 原始时间戳
    final storeLogs = await db.query('store_logs');
    expect(storeLogs.length, 1);
    expect(storeLogs.first['timestamp'], '2026-07-28T12:20:27');

    // 留痕
    final traces = await db.query('app_settings', where: "key = 'last_schema_migration'");
    expect(traces, isNotEmpty);
    expect((traces.first['value'] as String).contains('v8_import:'), isTrue);

    // 幂等：再次打开不重复导入
    final db2 = await DatabaseService.instance.database;
    expect((await db2.query('store_logs')).length, 1);
    expect((await db2.query('members')).length, 3);

    await db2.close();
    await tempDir.delete(recursive: true);
  });

  test('并发访问 database：只初始化一次，接管合并不被重复/并发执行', () async {
    // 重置单例（上一个测试已关闭连接并删除临时库）
    await DatabaseService.instance.close();

    final tempDir = await Directory.systemTemp.createTemp('legacy_concurrent_');
    await createV8(p.join(tempDir.path, 'steplife_v8.db'));
    await createBrokenV9(p.join(tempDir.path, 'steplife_v9.db'));
    databaseFactory.setDatabasesPath(tempDir.path);

    // 模拟 5 个 Provider 启动时并发触发 database 初始化
    final results = await Future.wait([
      for (var i = 0; i < 5; i++)
        DatabaseService.instance.database.then((db) async {
          final members = await db.query('members');
          final cats = await db.query('store_categories');
          return {'members': members.length, 'cats': cats.length};
        }),
    ]);

    for (final r in results) {
      expect(r['members'], 3);
      expect(r['cats'], 2);
    }

    final db = await DatabaseService.instance.database;
    final traces = await db.query('app_settings', where: "key = 'last_schema_migration'");
    expect(traces.length, 1, reason: '接管合并只能执行一次');
    expect((traces.first['value'] as String).contains('v8_import:'), isTrue);

    // 幂等：再次并发访问不重复导入
    await Future.wait([
      for (var i = 0; i < 3; i++) DatabaseService.instance.database,
    ]);
    expect((await db.query('store_logs')).length, 1);

    await db.close();
    await tempDir.delete(recursive: true);
  });
}
