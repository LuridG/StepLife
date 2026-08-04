import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../cache/cache_manager.dart';
import '../../features/profile/domain/user_profile.dart';
import '../../features/step_tracker/domain/step_models.dart';
import '../../features/chore_tracker/domain/chore_models.dart';
import '../../features/store_journal/domain/store_models.dart';
import '../../features/store_journal/domain/life_templates.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();
  static Database? _database;
  static Future<Database>? _initFuture;

  DatabaseService._internal();

  /// 并发安全：多个 Provider 启动时同时访问 database，
  /// 只执行一次 _initDatabase（含 v8→v9 迁移/接管合并），其余调用共享同一 Future。
  Future<Database> get database {
    final existing = _database;
    if (existing != null) return Future.value(existing);
    final pending = _initFuture;
    if (pending != null) return pending;
    final future = _initDatabase().then(
      (db) {
        _database = db;
        _initFuture = null;
        return db;
      },
      onError: (Object e, StackTrace st) {
        _initFuture = null;
        throw e;
      },
    );
    _initFuture = future;
    return future;
  }

  /// 当前数据库文件完整路径（WebDAV 备份 / 缓存统计用）
  Future<String> get databaseFilePath async {
    final db = await database;
    return db.path;
  }

  /// 关闭数据库连接（恢复备份前调用，随后访问 database 会重新打开）
  Future<void> close() async {
    final db = _database;
    _database = null;
    _initFuture = null;
    if (db != null) {
      try {
        await db.close();
      } catch (_) {}
    }
  }

  /// 强制 WAL checkpoint，保证复制出的快照文件完整
  Future<void> checkpoint() async {
    final db = await database;
    try {
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {}
  }

  /// 一致性快照：VACUUM INTO 生成完整独立备份文件（WAL 安全）
  Future<void> vacuumInto(String targetPath) async {
    final db = await database;
    final escaped = targetPath.replaceAll("'", "''");
    await db.rawQuery("VACUUM INTO '$escaped'");
  }

  static const List<String> _syncTables = [
    'user_profile',
    'routes',
    'step_logs',
    'route_measurements',
    'members',
    'chore_items',
    'chore_logs',
    'store_categories',
    'store_items',
    'store_logs',
    'store_menu_items',
  ];

  /// 只读校验快照/备份文件：完整性 + 各表行数
  Future<Map<String, Object>> verifySnapshot(String path) async {
    final db = await openDatabase(path, readOnly: true);
    try {
      final integrity = await db.rawQuery('PRAGMA integrity_check');
      final ok =
          integrity.isNotEmpty &&
          integrity.first.values.first.toString() == 'ok';
      final counts = <String, int>{};
      for (final t in _syncTables) {
        try {
          final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $t');
          counts[t] = (rows.first['c'] as num?)?.toInt() ?? 0;
        } catch (_) {}
      }
      return {'ok': ok, 'counts': counts};
    } finally {
      await db.close();
    }
  }

  /// 当前库各关键表行数统计
  Future<Map<String, int>> tableCounts() async {
    final db = await database;
    final counts = <String, int>{};
    for (final t in _syncTables) {
      try {
        final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $t');
        counts[t] = (rows.first['c'] as num?)?.toInt() ?? 0;
      } catch (_) {}
    }
    return counts;
  }

  /// 恢复后重映射图片路径：失效的绝对路径按文件名指向当前缓存目录
  Future<int> relinkImagesAfterRestore() async {
    final db = await database;
    final imagesDir = await CacheManager.instance.imagesDir();
    final tmdbDir = await CacheManager.instance.tmdbDir();
    var relinked = 0;

    Future<String> fix(String path) async {
      if (path.isEmpty) return path;
      if (await File(path).exists()) return path;
      final name = basename(path);
      for (final dir in [imagesDir, tmdbDir]) {
        final candidate = join(dir.path, name);
        if (await File(candidate).exists()) {
          relinked++;
          return candidate;
        }
      }
      return path;
    }

    // store_items.imagesJson：JSON 数组形式的图片列表
    final items = await db.query('store_items', columns: ['id', 'imagesJson']);
    for (final row in items) {
      final id = row['id'] as int;
      final raw = (row['imagesJson'] as String?) ?? '[]';
      try {
        final list = (jsonDecode(raw) as List).cast<String>();
        var changed = false;
        final fixed = <String>[];
        for (final img in list) {
          final f = await fix(img);
          if (f != img) changed = true;
          fixed.add(f);
        }
        if (changed) {
          await db.update(
            'store_items',
            {'imagesJson': jsonEncode(fixed)},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      } catch (_) {}
    }

    // store_menu_items.imagePath：菜品图片
    final menus = await db.query(
      'store_menu_items',
      columns: ['id', 'imagePath'],
    );
    for (final row in menus) {
      final id = row['id'] as int;
      final img = row['imagePath'] as String?;
      if (img == null || img.isEmpty) continue;
      final f = await fix(img);
      if (f != img) {
        await db.update(
          'store_menu_items',
          {'imagePath': f},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }
    return relinked;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final oldPath = join(dbPath, 'steplife_v8.db');
    final path = join(dbPath, 'steplife_v9.db');

    // 非破坏迁移：升级前自动备份旧库（仅当旧库存在且新库尚未创建时）
    if (await File(oldPath).exists() && !(await File(path).exists())) {
      await _backupLegacyDatabase(oldPath, dbPath);
      // 关键：把 v8 数据原样复制为 v9 文件，随后 openDatabase(version:9)
      // 会触发 onUpgrade(8→9)，由 migrateV8ToV9 完成真实的数据迁移（含 WAL 数据）
      await File(oldPath).copy(path);
      for (final suffix in ['-wal', '-shm']) {
        final side = File(oldPath + suffix);
        if (await side.exists()) {
          try {
            await side.copy(path + suffix);
          } catch (_) {}
        }
      }
    }

    final db = await openDatabase(
      path,
      version: 9,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: (db) async {
        try {
          await db.execute('ALTER TABLE members ADD COLUMN birthDate TEXT');
        } catch (_) {}
        // 餐饮菜单（幂等，兼容已存在的库）
        try {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS store_menu_items (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              storeId INTEGER NOT NULL,
              name TEXT NOT NULL,
              price REAL NOT NULL DEFAULT 0,
              imagePath TEXT,
              sortOrder INTEGER NOT NULL DEFAULT 0,
              specsJson TEXT NOT NULL DEFAULT '[]',
              createdAt TEXT NOT NULL
            )
          ''');
        } catch (_) {}
        try {
          await db.execute(
            "ALTER TABLE store_logs ADD COLUMN menuItemIdsJson TEXT NOT NULL DEFAULT '[]'",
          );
        } catch (_) {}
        try {
          await db.execute(
            "ALTER TABLE store_logs ADD COLUMN menuNamesJson TEXT NOT NULL DEFAULT '[]'",
          );
        } catch (_) {}
        try {
          await db.execute(
            "ALTER TABLE store_logs ADD COLUMN menuSpecsJson TEXT NOT NULL DEFAULT '[]'",
          );
        } catch (_) {}
        try {
          await db.execute(
            "ALTER TABLE store_menu_items ADD COLUMN specsJson TEXT NOT NULL DEFAULT '[]'",
          );
        } catch (_) {}
        // 菜品打分：1=推荐招牌菜 / -1=不推荐 / 0=未打分（幂等，兼容旧库）
        try {
          await db.execute(
            'ALTER TABLE store_menu_items ADD COLUMN rating INTEGER NOT NULL DEFAULT 0',
          );
        } catch (_) {}
        // 路线测量记录表（兼容已存在的旧库）
        try {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS route_measurements (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              routeId INTEGER NOT NULL,
              steps INTEGER NOT NULL,
              multiplier REAL NOT NULL DEFAULT 1.0,
              computedSteps INTEGER NOT NULL,
              measuredBy TEXT NOT NULL DEFAULT '自己',
              createdAt TEXT NOT NULL
            )
          ''');
        } catch (_) {}
      },
    );

    // 历史缺陷修复：旧版曾以“全新库”方式创建 v9（未迁移 v8 数据）。
    // 若 v9 无迁移留痕且 v8 仍存在，则做一次性安全接管合并，绝不丢弃任何一方数据。
    if (await File(oldPath).exists()) {
      final trace = await db.query(
        'app_settings',
        columns: ['key'],
        where: "key = 'last_schema_migration'",
        limit: 1,
      );
      if (trace.isEmpty) {
        // 接管合并失败绝不阻断应用启动：写入错误留痕，下次启动自动重试
        try {
          await _importLegacyV8Data(db, oldPath);
          final now = DateTime.now();
          String two(int v) => v.toString().padLeft(2, '0');
          final stamp =
              '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
          await db.insert('app_settings', {
            'key': 'last_schema_migration',
            'value': 'v8_import:$stamp:ok',
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        } catch (e) {
          try {
            await db.insert('app_settings', {
              'key': 'v8_import_error',
              'value': '$e',
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          } catch (_) {}
        }
      }
    }

    return db;
  }

  /// 升级前备份旧 v8 库（含 WAL/SHM），保留最近 3 份，绝不动旧库原文件
  Future<void> _backupLegacyDatabase(String oldPath, String dbPath) async {
    try {
      final now = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final stamp =
          '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
      final backupPath = join(dbPath, 'steplife_v8_backup_$stamp.db');
      await File(oldPath).copy(backupPath);
      for (final suffix in ['-wal', '-shm']) {
        final side = File(oldPath + suffix);
        if (await side.exists()) {
          try {
            await side.copy(backupPath + suffix);
          } catch (_) {}
        }
      }
      // 保留最近 3 份备份
      final dir = Directory(dbPath);
      final backups = await dir
          .list()
          .where(
            (e) =>
                e is File &&
                basename(e.path).startsWith('steplife_v8_backup_') &&
                basename(e.path).endsWith('.db'),
          )
          .cast<File>()
          .toList();
      backups.sort((a, b) => b.path.compareTo(a.path));
      for (final old in backups.skip(3)) {
        try {
          await old.delete();
        } catch (_) {}
      }
    } catch (e) {
      // 备份失败：拒绝升级，避免冒数据风险
      throw StateError('升级前备份旧数据库失败，已中止升级: $e');
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    // 个人身体参数与视图偏好表
    await db.execute('''
      CREATE TABLE user_profile (
        id INTEGER PRIMARY KEY DEFAULT 1,
        heightCm REAL,
        weightKg REAL,
        gender TEXT,
        age INTEGER,
        customStrideCm REAL,
        preferredViewMode TEXT DEFAULT 'card'
      )
    ''');

    // 客观路线定义表
    await db.execute('''
      CREATE TABLE routes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        measuredBy TEXT NOT NULL DEFAULT '自己',
        refSteps INTEGER DEFAULT 2000,
        isLocked INTEGER DEFAULT 0,
        createdAt TEXT NOT NULL
      )
    ''');

    // 路线单程步数测量记录表（多次测量取平均）
    await db.execute('''
      CREATE TABLE route_measurements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        routeId INTEGER NOT NULL,
        steps INTEGER NOT NULL,
        multiplier REAL NOT NULL DEFAULT 1.0,
        computedSteps INTEGER NOT NULL,
        measuredBy TEXT NOT NULL DEFAULT '自己',
        createdAt TEXT NOT NULL
      )
    ''');

    // 行走打卡记录表
    await db.execute('''
      CREATE TABLE step_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        routeId INTEGER,
        routeName TEXT NOT NULL,
        walkerName TEXT NOT NULL DEFAULT '自己',
        timesCount INTEGER NOT NULL DEFAULT 1,
        steps INTEGER NOT NULL,
        durationMinutes INTEGER NOT NULL,
        distanceKm REAL NOT NULL,
        caloriesKcal REAL NOT NULL,
        timestamp TEXT NOT NULL
      )
    ''');

    // 统一成员信息表
    await db.execute('''
      CREATE TABLE members (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        gender TEXT DEFAULT '男',
        heightCm REAL DEFAULT 170.0,
        weightKg REAL DEFAULT 65.0,
        age INTEGER DEFAULT 25,
        customStrideCm REAL,
        avatarIcon TEXT,
        colorValue INTEGER
      )
    ''');

    // 家务事项定义表
    await db.execute('''
      CREATE TABLE chore_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        category TEXT,
        iconName TEXT,
        isQuantifiable INTEGER DEFAULT 0,
        unit TEXT DEFAULT '次'
      )
    ''');

    // 家务习惯日志表
    await db.execute('''
      CREATE TABLE chore_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        choreId INTEGER NOT NULL,
        choreTitle TEXT NOT NULL,
        memberIdsJson TEXT NOT NULL,
        memberNamesJson TEXT NOT NULL,
        memo TEXT,
        value REAL,
        timestamp TEXT NOT NULL
      )
    ''');

    // 【生活记录】分类表
    await db.execute('''
      CREATE TABLE store_categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        iconName TEXT DEFAULT 'storefront',
        templateKey TEXT NOT NULL DEFAULT 'generic',
        extraFieldsJson TEXT NOT NULL DEFAULT '[]'
      )
    ''');

    // 【生活记录】通用生活项目表 (仅客观属性，初次登记不设消费)
    await db.execute('''
      CREATE TABLE store_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        rating REAL NOT NULL DEFAULT 5.0,
        imagesJson TEXT NOT NULL,
        address TEXT,
        notes TEXT,
        extrasJson TEXT NOT NULL DEFAULT '{}',
        createdAt TEXT NOT NULL
      )
    ''');

    // 【生活记录】打卡履约日志表 (含分钟级时间、消费金额、同行成员列表)
    await db.execute('''
      CREATE TABLE store_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        storeId INTEGER NOT NULL,
        storeName TEXT NOT NULL,
        cost REAL,
        visitorIdsJson TEXT NOT NULL DEFAULT '[]',
        visitorNamesJson TEXT NOT NULL DEFAULT '[]',
        memo TEXT,
        extrasJson TEXT NOT NULL DEFAULT '{}',
        menuItemIdsJson TEXT NOT NULL DEFAULT '[]',
        menuNamesJson TEXT NOT NULL DEFAULT '[]',
        menuSpecsJson TEXT NOT NULL DEFAULT '[]',
        timestamp TEXT NOT NULL
      )
    ''');

    // 全局设置表
    await db.execute('''
      CREATE TABLE store_menu_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        storeId INTEGER NOT NULL,
        name TEXT NOT NULL,
        price REAL NOT NULL DEFAULT 0,
        imagePath TEXT,
        sortOrder INTEGER NOT NULL DEFAULT 0,
        specsJson TEXT NOT NULL DEFAULT '[]',
        rating INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL
      );

      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    // 初始化预设家庭成员
    await db.insert('members', {
      'name': '成员A',
      'gender': '男',
      'heightCm': 175.0,
      'weightKg': 70.0,
      'age': 28,
      'avatarIcon': 'person',
      'colorValue': 0xFF6366F1,
    });
    await db.insert('members', {
      'name': '成员B',
      'gender': '女',
      'heightCm': 162.0,
      'weightKg': 52.0,
      'age': 26,
      'avatarIcon': 'person_outline',
      'colorValue': 0xFF10B981,
    });
    await db.insert('members', {
      'name': '成员C',
      'gender': '男',
      'heightCm': 150.0,
      'weightKg': 45.0,
      'age': 14,
      'avatarIcon': 'face',
      'colorValue': 0xFFF43F5E,
    });

    await db.insert('routes', {
      'name': '小区公园慢跑圈',
      'description': '绕小区中央公园绿道一圈',
      'measuredBy': '成员A',
      'refSteps': 2500,
      'isLocked': 0,
      'createdAt': DateTime.now().toIso8601String(),
    });

    await db.insert('chore_items', {
      'title': '扫地拖地',
      'category': '日常家务',
      'iconName': 'cleaning_services',
      'isQuantifiable': 0,
      'unit': '次',
    });

    // 默认通用生活分类（绑定对应模板，新建即带出专属字段）
    await db.insert('store_categories', {
      'name': '影视剧集',
      'iconName': 'movie',
      'templateKey': 'movie',
    });
    await db.insert('store_categories', {
      'name': '书籍阅读',
      'iconName': 'book',
      'templateKey': 'book',
    });
    await db.insert('store_categories', {
      'name': '餐饮美食',
      'iconName': 'restaurant',
      'templateKey': 'dining',
    });
    await db.insert('store_categories', {
      'name': '景点场所',
      'iconName': 'place',
      'templateKey': 'place',
    });

    // 预设默认探店/影视示例项目 (客观属性)
    final store1Id = await db.insert('store_items', {
      'name': '流浪地球2 (4K IMAX)',
      'category': '影视剧集',
      'rating': 4.9,
      'imagesJson': '[]',
      'address': '万达影城 3号厅',
      'notes': '视觉特效与宏大叙事极其震撼，硬核科幻巅峰',
      'createdAt': DateTime.now().toIso8601String(),
    });
    final store2Id = await db.insert('store_items', {
      'name': '川湘阁精品小炒',
      'category': '餐饮美食',
      'rating': 4.8,
      'imagesJson': '[]',
      'address': '中山路 128 号底商',
      'notes': '招牌剁椒鱼头与小炒肉味道绝佳',
      'createdAt': DateTime.now().toIso8601String(),
    });

    // 预设初次打卡履约数据 (分钟级时间 + 消费 + 成员)
    await db.insert('store_logs', {
      'storeId': store1Id,
      'storeName': '流浪地球2 (4K IMAX)',
      'cost': 90.0,
      'visitorIdsJson': '[1, 2]',
      'visitorNamesJson': '["成员A", "成员B"]',
      'memo': '影院双人观影，效果拔群',
      'timestamp': DateTime.now()
          .subtract(const Duration(days: 2))
          .toIso8601String(),
    });
    await db.insert('store_logs', {
      'storeId': store2Id,
      'storeName': '川湘阁精品小炒',
      'cost': 136.0,
      'visitorIdsJson': '[1, 2, 3]',
      'visitorNamesJson': '["成员A", "成员B", "成员C"]',
      'memo': '家庭聚餐，剁椒鱼头非常地道',
      'timestamp': DateTime.now()
          .subtract(const Duration(days: 5))
          .toIso8601String(),
    });
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // 兼容更早版本：补 visitor 列
    if (oldVersion < 8) {
      try {
        await db.execute(
          'ALTER TABLE store_logs ADD COLUMN visitorIdsJson TEXT NOT NULL DEFAULT "[]"',
        );
        await db.execute(
          'ALTER TABLE store_logs ADD COLUMN visitorNamesJson TEXT NOT NULL DEFAULT "[]"',
        );
      } catch (_) {}
    }
    // Schema v9：非破坏迁移（只增列 + 新表，全程单事务，失败整体回滚）
    if (oldVersion < 9) {
      await migrateV8ToV9(db);
    }
  }

  /// 历史缺陷修复：旧版曾以“全新库”方式创建 v9（未迁移 v8 数据）。
  /// 这里做一次性幂等接管合并：v8 中 v9 缺失的数据补插进去，v9 已有数据保持不变。
  Future<void> _importLegacyV8Data(Database db, String oldPath) async {
    final legacy = await openDatabase(oldPath);
    try {
      await db.transaction((txn) async {
        await txn.execute(
          'CREATE TABLE IF NOT EXISTS app_settings (key TEXT PRIMARY KEY, value TEXT)',
        );

        // 成员：同名缺失补插；出生日期为空时回填 v8 数据
        final members = await legacy.query('members');
        for (final m in members) {
          final name = m['name'] as String;
          final exists = await txn.query(
            'members',
            where: 'name = ?',
            whereArgs: [name],
            limit: 1,
          );
          if (exists.isEmpty) {
            final row = Map<String, dynamic>.from(m)..remove('id');
            await txn.insert('members', row);
          } else {
            final birth = m['birthDate'] as String?;
            if (birth != null && birth.isNotEmpty) {
              final cur = exists.first['birthDate'] as String?;
              if (cur == null || cur.isEmpty) {
                await txn.update(
                  'members',
                  {'birthDate': birth},
                  where: 'id = ?',
                  whereArgs: [exists.first['id']],
                );
              }
            }
          }
        }

        // 路线 / 家务项 / 生活分类 / 店铺项：按自然键去重补插
        Future<void> importByKey({
          required String table,
          required List<Map<String, Object?>> rows,
          required String keyColumn,
          List<String> extraKeyColumns = const [],
        }) async {
          for (final row in rows) {
            final where = <String>[];
            final args = <Object?>[];
            where.add('$keyColumn = ?');
            args.add(row[keyColumn]);
            for (final col in extraKeyColumns) {
              where.add('$col = ?');
              args.add(row[col]);
            }
            final dup = await txn.query(
              table,
              where: where.join(' AND '),
              whereArgs: args,
              limit: 1,
            );
            if (dup.isEmpty) {
              final insertRow = Map<String, dynamic>.from(row)..remove('id');
              if (table == 'store_categories') {
                insertRow['templateKey'] = LifeTemplates.matchTemplateKey(
                  row['name']?.toString() ?? '',
                );
              }
              await txn.insert(table, insertRow);
            }
          }
        }

        await importByKey(
          table: 'routes',
          rows: await legacy.query('routes'),
          keyColumn: 'name',
        );
        await importByKey(
          table: 'chore_items',
          rows: await legacy.query('chore_items'),
          keyColumn: 'title',
        );
        await importByKey(
          table: 'store_categories',
          rows: await legacy.query('store_categories'),
          keyColumn: 'name',
        );
        await importByKey(
          table: 'store_items',
          rows: await legacy.query('store_items'),
          keyColumn: 'name',
          extraKeyColumns: ['category'],
        );

        // 修复历史缺陷创建的 v9：分类全部为 generic，按名称重新绑定模板
        final cats = await txn.query('store_categories');
        for (final cat in cats) {
          final name = cat['name'] as String? ?? '';
          final key = LifeTemplates.matchTemplateKey(name);
          final cur = cat['templateKey'] as String? ?? 'generic';
          if (key != 'generic' && cur == 'generic') {
            await txn.update(
              'store_categories',
              {'templateKey': key},
              where: 'id = ?',
              whereArgs: [cat['id']],
            );
          }
        }

        // 打卡日志：按 标题 + 时间戳 去重补插（自增 id，避免与 v9 已有记录冲突）
        Future<void> importLogs(
          String table,
          List<Map<String, Object?>> rows,
          List<String> dedupCols,
        ) async {
          for (final row in rows) {
            final where = dedupCols.map((c) => '$c = ?').join(' AND ');
            final args = dedupCols.map((c) => row[c]).toList();
            final dup = await txn.query(
              table,
              where: where,
              whereArgs: args,
              limit: 1,
            );
            if (dup.isEmpty) {
              final insertRow = Map<String, dynamic>.from(row)..remove('id');
              await txn.insert(table, insertRow);
            }
          }
        }

        await importLogs('chore_logs', await legacy.query('chore_logs'), [
          'choreTitle',
          'timestamp',
        ]);
        await importLogs('step_logs', await legacy.query('step_logs'), [
          'routeName',
          'timestamp',
        ]);
        // 生活打卡日志：按 店铺+金额+备注 语义去重（种子副本时间戳不同），
        // 命中即回填 v8 的原始时间戳，避免把同一笔打卡复制成两条
        {
          final rows = await legacy.query('store_logs');
          for (final row in rows) {
            final dup = await txn.query(
              'store_logs',
              where: 'storeName = ? AND cost = ? AND memo = ?',
              whereArgs: [row['storeName'], row['cost'], row['memo']],
              limit: 1,
            );
            if (dup.isEmpty) {
              final insertRow = Map<String, dynamic>.from(row)..remove('id');
              await txn.insert('store_logs', insertRow);
            } else {
              final ts = row['timestamp'];
              if (ts != null) {
                await txn.update(
                  'store_logs',
                  {'timestamp': ts},
                  where: 'storeName = ? AND cost = ? AND memo = ?',
                  whereArgs: [row['storeName'], row['cost'], row['memo']],
                );
              }
            }
          }
        }
      });
    } finally {
      await legacy.close();
    }
  }

  /// v8 → v9 迁移：备份已在 openDatabase 前完成；此处仅做增量变更 + 对账
  /// 公开以便迁移测试直接调用
  Future<void> migrateV8ToV9(Database db) async {
    final before = await _countRows(db);
    await db.transaction((txn) async {
      // 幂等：列已存在则跳过，绝不重建/清空表
      if (!await _hasColumn(txn, 'store_categories', 'templateKey')) {
        await txn.execute(
          "ALTER TABLE store_categories ADD COLUMN templateKey TEXT NOT NULL DEFAULT 'generic'",
        );
      }
      if (!await _hasColumn(txn, 'store_categories', 'extraFieldsJson')) {
        await txn.execute(
          "ALTER TABLE store_categories ADD COLUMN extraFieldsJson TEXT NOT NULL DEFAULT '[]'",
        );
      }
      if (!await _hasColumn(txn, 'store_items', 'extrasJson')) {
        await txn.execute(
          "ALTER TABLE store_items ADD COLUMN extrasJson TEXT NOT NULL DEFAULT '{}'",
        );
      }
      if (!await _hasColumn(txn, 'store_logs', 'extrasJson')) {
        await txn.execute(
          "ALTER TABLE store_logs ADD COLUMN extrasJson TEXT NOT NULL DEFAULT '{}'",
        );
      }
      await txn.execute(
        'CREATE TABLE IF NOT EXISTS app_settings (key TEXT PRIMARY KEY, value TEXT)',
      );

      // 分类按名称智能绑定模板
      final cats = await txn.query('store_categories');
      for (final cat in cats) {
        final name = cat['name'] as String? ?? '';
        final key = LifeTemplates.matchTemplateKey(name);
        await txn.update(
          'store_categories',
          {'templateKey': key},
          where: 'id = ?',
          whereArgs: [cat['id']],
        );
      }

      // 迁移视图偏好：user_profile.preferredViewMode → app_settings（旧字段保留作回退）
      final profile = await txn.query(
        'user_profile',
        where: 'id = 1',
        limit: 1,
      );
      if (profile.isNotEmpty) {
        final mode = profile.first['preferredViewMode'] as String?;
        if (mode != null && mode.isNotEmpty) {
          await txn.insert('app_settings', {
            'key': 'preferredViewMode',
            'value': mode,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }

      // 迁移留痕（先写入，对账失败则回滚整体清除）
      final now = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final stamp =
          '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
      await txn.insert('app_settings', {
        'key': 'last_schema_migration',
        'value': 'v8_to_v9:$stamp:ok',
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // 行数对账：迁移前后每张表行数必须一致
      final after = await _countRows(txn);
      for (final entry in before.entries) {
        final afterCount = after[entry.key];
        if (afterCount != entry.value) {
          throw StateError(
            '迁移行数对账失败: ${entry.key} before=${entry.value} after=${afterCount?.toString() ?? 'null'}',
          );
        }
      }

      // 新列抽查
      final badItems = await txn.rawQuery(
        "SELECT COUNT(*) AS c FROM store_items WHERE extrasJson IS NULL OR extrasJson = ''",
      );
      if ((badItems.first['c'] as int?) != 0) {
        throw StateError('store_items.extrasJson 存在空值，迁移中止');
      }
      final badCats = await txn.rawQuery(
        "SELECT COUNT(*) AS c FROM store_categories WHERE templateKey IS NULL OR templateKey = ''",
      );
      if ((badCats.first['c'] as int?) != 0) {
        throw StateError('store_categories.templateKey 存在空值，迁移中止');
      }
    });
    // 事务外校验整体完整性
    final integrity = await db.rawQuery('PRAGMA integrity_check');
    if (integrity.isNotEmpty && integrity.first.values.first != 'ok') {
      throw StateError('迁移后 integrity_check 未通过: $integrity');
    }
  }

  /// 检测表是否已包含某列（幂等迁移用）
  Future<bool> _hasColumn(
    DatabaseExecutor db,
    String table,
    String column,
  ) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.any((r) => r['name'] == column);
  }

  /// 统计各表行数（迁移前后对账用）
  Future<Map<String, int>> _countRows(DatabaseExecutor db) async {
    const tables = [
      'user_profile',
      'routes',
      'step_logs',
      'members',
      'chore_items',
      'chore_logs',
      'store_categories',
      'store_items',
      'store_logs',
    ];
    final result = <String, int>{};
    for (final t in tables) {
      final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $t');
      result[t] = (rows.first['c'] as int?) ?? 0;
    }
    return result;
  }

  // --- View Mode Persistence ---
  Future<String> getPreferredViewMode() async {
    // 新读 app_settings，缺省回退旧 user_profile.preferredViewMode（向后兼容）
    final appMode = await getSetting('preferredViewMode');
    if (appMode != null && appMode.isNotEmpty) {
      return appMode;
    }
    final db = await database;
    final maps = await db.query(
      'user_profile',
      columns: ['preferredViewMode'],
      limit: 1,
    );
    if (maps.isNotEmpty && maps.first['preferredViewMode'] != null) {
      return maps.first['preferredViewMode'] as String;
    }
    return 'card';
  }

  Future<void> savePreferredViewMode(String mode) async {
    await setSetting('preferredViewMode', mode);
    // 同步回写旧字段，保证旧版本 App 降级后偏好仍一致
    final db = await database;
    final existing = await db.query('user_profile', limit: 1);
    if (existing.isNotEmpty) {
      await db.update('user_profile', {
        'preferredViewMode': mode,
      }, where: 'id = 1');
    } else {
      await db.insert('user_profile', {'id': 1, 'preferredViewMode': mode});
    }
  }

  // --- App Settings CRUD ---
  Future<String?> getSetting(String key) async {
    final db = await database;
    final rows = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert('app_settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, String>> getAllSettings() async {
    final db = await database;
    final rows = await db.query('app_settings');
    return {
      for (final r in rows) r['key'] as String: (r['value'] as String?) ?? '',
    };
  }

  // --- Profile CRUD ---
  Future<UserProfile> getUserProfile() async {
    final db = await database;
    final maps = await db.query('user_profile', limit: 1);
    if (maps.isNotEmpty) {
      return UserProfile.fromMap(maps.first);
    } else {
      const defaultProfile = UserProfile();
      await saveUserProfile(defaultProfile);
      return defaultProfile;
    }
  }

  Future<void> saveUserProfile(UserProfile profile) async {
    final db = await database;
    await db.insert('user_profile', {
      'id': 1,
      ...profile.toMap(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // --- Routes & Step Logs CRUD ---
  Future<List<RouteItem>> getRoutes() async {
    final db = await database;
    final maps = await db.query('routes', orderBy: 'id DESC');
    return maps.map((e) => RouteItem.fromMap(e)).toList();
  }

  Future<int> insertRoute(RouteItem route) async {
    final db = await database;
    return await db.insert('routes', route.toMap());
  }

  Future<void> updateRoute(RouteItem route) async {
    final db = await database;
    await db.update(
      'routes',
      route.toMap(),
      where: 'id = ?',
      whereArgs: [route.id],
    );
  }

  Future<void> updateRouteLock(int routeId, bool isLocked) async {
    final db = await database;
    await db.update(
      'routes',
      {'isLocked': isLocked ? 1 : 0},
      where: 'id = ?',
      whereArgs: [routeId],
    );
  }

  Future<void> deleteRoute(int routeId) async {
    final db = await database;
    await db.delete('routes', where: 'id = ?', whereArgs: [routeId]);
  }

  Future<List<RouteMeasurement>> getRouteMeasurements() async {
    final db = await database;
    final maps = await db.query(
      'route_measurements',
      orderBy: 'createdAt DESC, id DESC',
    );
    return maps.map((e) => RouteMeasurement.fromMap(e)).toList();
  }

  Future<int> insertRouteMeasurement(RouteMeasurement m) async {
    final db = await database;
    return await db.insert('route_measurements', m.toMap());
  }

  Future<void> deleteRouteMeasurement(int id) async {
    final db = await database;
    await db.delete('route_measurements', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<StepLog>> getStepLogs() async {
    final db = await database;
    final maps = await db.query('step_logs', orderBy: 'timestamp DESC');
    return maps.map((e) => StepLog.fromMap(e)).toList();
  }

  Future<int> insertStepLog(StepLog log) async {
    final db = await database;
    return await db.insert('step_logs', log.toMap());
  }

  Future<void> deleteStepLog(int logId) async {
    final db = await database;
    await db.delete('step_logs', where: 'id = ?', whereArgs: [logId]);
  }

  // --- Chores & Members CRUD ---
  Future<List<Member>> getMembers() async {
    final db = await database;
    final maps = await db.query('members', orderBy: 'id ASC');
    return maps.map((e) => Member.fromMap(e)).toList();
  }

  Future<int> insertMember(Member member) async {
    final db = await database;
    return await db.insert('members', member.toMap());
  }

  Future<void> updateMember(Member member) async {
    final db = await database;
    await db.update(
      'members',
      member.toMap(),
      where: 'id = ?',
      whereArgs: [member.id],
    );
  }

  Future<void> deleteMember(int id) async {
    final db = await database;
    await db.delete('members', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<ChoreItem>> getChoreItems() async {
    final db = await database;
    final maps = await db.query('chore_items', orderBy: 'id ASC');
    return maps.map((e) => ChoreItem.fromMap(e)).toList();
  }

  Future<int> insertChoreItem(ChoreItem item) async {
    final db = await database;
    return await db.insert('chore_items', item.toMap());
  }

  Future<void> updateChoreItem(ChoreItem item) async {
    final db = await database;
    await db.update(
      'chore_items',
      item.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  /// 删除家务事项（连同其全部打卡记录一并删除）
  Future<void> deleteChoreItem(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('chore_logs', where: 'choreId = ?', whereArgs: [id]);
      await txn.delete('chore_items', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<List<ChoreLog>> getChoreLogs() async {
    final db = await database;
    final maps = await db.query('chore_logs', orderBy: 'timestamp DESC');
    return maps.map((e) => ChoreLog.fromMap(e)).toList();
  }

  Future<int> insertChoreLog(ChoreLog log) async {
    final db = await database;
    return await db.insert('chore_logs', log.toMap());
  }

  Future<void> deleteChoreLog(int logId) async {
    final db = await database;
    await db.delete('chore_logs', where: 'id = ?', whereArgs: [logId]);
  }

  // --- Store / Life Journal CRUD ---
  Future<List<StoreCategory>> getStoreCategories() async {
    final db = await database;
    final maps = await db.query('store_categories', orderBy: 'id ASC');
    return maps.map((e) => StoreCategory.fromMap(e)).toList();
  }

  Future<int> insertStoreCategory(StoreCategory category) async {
    final db = await database;
    return await db.insert(
      'store_categories',
      category.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> updateStoreCategory(
    int catId,
    String newName,
    String oldName,
  ) async {
    final db = await database;
    await db.update(
      'store_categories',
      {'name': newName},
      where: 'id = ?',
      whereArgs: [catId],
    );
    await db.update(
      'store_items',
      {'category': newName},
      where: 'category = ?',
      whereArgs: [oldName],
    );
  }

  /// 按名称重新匹配模板绑定（设置中心"恢复内置模板"）
  Future<int> resetTemplateBindings() async {
    final db = await database;
    final cats = await db.query('store_categories');
    var updated = 0;
    for (final cat in cats) {
      final key = LifeTemplates.matchTemplateKey(cat['name'] as String? ?? '');
      await db.update(
        'store_categories',
        {'templateKey': key},
        where: 'id = ?',
        whereArgs: [cat['id']],
      );
      updated++;
    }
    return updated;
  }

  /// 手动修改分类绑定的模板
  Future<void> updateCategoryTemplate(int catId, String templateKey) async {
    final db = await database;
    await db.update(
      'store_categories',
      {'templateKey': templateKey},
      where: 'id = ?',
      whereArgs: [catId],
    );
  }

  /// 保存分类自定义字段定义
  Future<void> updateCategoryExtraFields(
    int catId,
    String extraFieldsJson,
  ) async {
    final db = await database;
    await db.update(
      'store_categories',
      {'extraFieldsJson': extraFieldsJson},
      where: 'id = ?',
      whereArgs: [catId],
    );
  }

  Future<void> deleteStoreCategory(int catId, String catName) async {
    final db = await database;
    await db.delete('store_categories', where: 'id = ?', whereArgs: [catId]);
    await db.update(
      'store_items',
      {'category': '通用未分类'},
      where: 'category = ?',
      whereArgs: [catName],
    );
  }

  Future<List<StoreItem>> getStoreItems() async {
    final db = await database;
    final maps = await db.query('store_items', orderBy: 'id DESC');
    return maps.map((e) => StoreItem.fromMap(e)).toList();
  }

  Future<int> insertStoreItem(StoreItem item) async {
    final db = await database;
    return await db.insert('store_items', item.toMap());
  }

  Future<void> updateStoreItem(StoreItem item) async {
    final db = await database;
    await db.update(
      'store_items',
      item.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<void> deleteStoreItem(int itemId) async {
    final db = await database;
    await db.delete('store_items', where: 'id = ?', whereArgs: [itemId]);
    await db.delete('store_logs', where: 'storeId = ?', whereArgs: [itemId]);
    await db.delete(
      'store_menu_items',
      where: 'storeId = ?',
      whereArgs: [itemId],
    );
  }

  Future<List<StoreLog>> getStoreLogs() async {
    final db = await database;
    final maps = await db.query('store_logs', orderBy: 'timestamp DESC');
    return maps.map((e) => StoreLog.fromMap(e)).toList();
  }

  Future<int> insertStoreLog(StoreLog log) async {
    final db = await database;
    return await db.insert('store_logs', log.toMap());
  }

  Future<void> deleteStoreLog(int logId) async {
    final db = await database;
    await db.delete('store_logs', where: 'id = ?', whereArgs: [logId]);
  }

  Future<void> updateStoreLog(StoreLog log) async {
    final db = await database;
    await db.update(
      'store_logs',
      log.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [log.id],
    );
  }

  // --- 餐饮菜单 CRUD ---
  Future<List<StoreMenuItem>> getStoreMenuItems() async {
    final db = await database;
    final maps = await db.query(
      'store_menu_items',
      orderBy: 'sortOrder ASC, id ASC',
    );
    return maps.map((e) => StoreMenuItem.fromMap(e)).toList();
  }

  Future<List<StoreMenuItem>> getMenuItemsForStore(int storeId) async {
    final db = await database;
    final maps = await db.query(
      'store_menu_items',
      where: 'storeId = ?',
      whereArgs: [storeId],
      orderBy: 'sortOrder ASC, id ASC',
    );
    return maps.map((e) => StoreMenuItem.fromMap(e)).toList();
  }

  Future<int> insertStoreMenuItem(StoreMenuItem item) async {
    final db = await database;
    return await db.insert('store_menu_items', item.toMap());
  }

  Future<void> updateStoreMenuItem(StoreMenuItem item) async {
    final db = await database;
    await db.update(
      'store_menu_items',
      item.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<void> deleteStoreMenuItem(int itemId) async {
    final db = await database;
    await db.delete('store_menu_items', where: 'id = ?', whereArgs: [itemId]);
  }

  Future<void> deleteStoreMenuItems(int storeId) async {
    final db = await database;
    await db.delete(
      'store_menu_items',
      where: 'storeId = ?',
      whereArgs: [storeId],
    );
  }
}
