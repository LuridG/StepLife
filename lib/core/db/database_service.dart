import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../../features/profile/domain/user_profile.dart';
import '../../features/step_tracker/domain/step_models.dart';
import '../../features/chore_tracker/domain/chore_models.dart';
import '../../features/store_journal/domain/store_models.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();
  static Database? _database;

  DatabaseService._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'steplife_v8.db');

    return await openDatabase(
      path,
      version: 8,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: (db) async {
        try {
          await db.execute('ALTER TABLE members ADD COLUMN birthDate TEXT');
        } catch (_) {}
      },
    );
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
        iconName TEXT DEFAULT 'storefront'
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
        timestamp TEXT NOT NULL
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
      'unit': '次'
    });

    // 默认通用生活分类
    await db.insert('store_categories', {'name': '影视剧集', 'iconName': 'movie'});
    await db.insert('store_categories', {'name': '书籍阅读', 'iconName': 'book'});
    await db.insert('store_categories', {'name': '餐饮美食', 'iconName': 'restaurant'});
    await db.insert('store_categories', {'name': '景点场所', 'iconName': 'place'});

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
      'timestamp': DateTime.now().subtract(const Duration(days: 2)).toIso8601String(),
    });
    await db.insert('store_logs', {
      'storeId': store2Id,
      'storeName': '川湘阁精品小炒',
      'cost': 136.0,
      'visitorIdsJson': '[1, 2, 3]',
      'visitorNamesJson': '["成员A", "成员B", "成员C"]',
      'memo': '家庭聚餐，剁椒鱼头非常地道',
      'timestamp': DateTime.now().subtract(const Duration(days: 5)).toIso8601String(),
    });
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 8) {
      try {
        await db.execute('ALTER TABLE store_logs ADD COLUMN visitorIdsJson TEXT NOT NULL DEFAULT "[]"');
        await db.execute('ALTER TABLE store_logs ADD COLUMN visitorNamesJson TEXT NOT NULL DEFAULT "[]"');
      } catch (_) {}
    }
  }

  // --- View Mode Persistence ---
  Future<String> getPreferredViewMode() async {
    final db = await database;
    final maps = await db.query('user_profile', columns: ['preferredViewMode'], limit: 1);
    if (maps.isNotEmpty && maps.first['preferredViewMode'] != null) {
      return maps.first['preferredViewMode'] as String;
    }
    return 'card';
  }

  Future<void> savePreferredViewMode(String mode) async {
    final db = await database;
    final existing = await db.query('user_profile', limit: 1);
    if (existing.isNotEmpty) {
      await db.update('user_profile', {'preferredViewMode': mode}, where: 'id = 1');
    } else {
      await db.insert('user_profile', {'id': 1, 'preferredViewMode': mode});
    }
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
    await db.insert(
      'user_profile',
      {'id': 1, ...profile.toMap()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
    await db.delete(
      'members',
      where: 'id = ?',
      whereArgs: [id],
    );
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
    return await db.insert('store_categories', category.toMap(), conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> updateStoreCategory(int catId, String newName, String oldName) async {
    final db = await database;
    await db.update('store_categories', {'name': newName}, where: 'id = ?', whereArgs: [catId]);
    await db.update('store_items', {'category': newName}, where: 'category = ?', whereArgs: [oldName]);
  }

  Future<void> deleteStoreCategory(int catId, String catName) async {
    final db = await database;
    await db.delete('store_categories', where: 'id = ?', whereArgs: [catId]);
    await db.update('store_items', {'category': '通用未分类'}, where: 'category = ?', whereArgs: [catName]);
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
}
