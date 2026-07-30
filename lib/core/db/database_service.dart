import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../../features/profile/domain/user_profile.dart';
import '../../features/step_tracker/domain/step_models.dart';
import '../../features/chore_tracker/domain/chore_models.dart';

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
    final path = join(dbPath, 'steplife_v5.db');

    return await openDatabase(
      path,
      version: 5,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // 个人身体参数表
    await db.execute('''
      CREATE TABLE user_profile (
        id INTEGER PRIMARY KEY DEFAULT 1,
        heightCm REAL,
        weightKg REAL,
        gender TEXT,
        age INTEGER,
        customStrideCm REAL
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

    // 统一成员信息表 (整合生理参数)
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

    // 初始化预设成员 (含差异化体貌生理数据)
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
    await db.insert('routes', {
      'name': '上下班地铁路线',
      'description': '起点：家南门，终点：地铁A口',
      'measuredBy': '成员B',
      'refSteps': 3200,
      'isLocked': 1,
      'createdAt': DateTime.now().toIso8601String(),
    });

    await db.insert('chore_items', {
      'title': '扫地拖地',
      'category': '日常家务',
      'iconName': 'cleaning_services',
      'isQuantifiable': 0,
      'unit': '次'
    });
    await db.insert('chore_items', {
      'title': '买菜记账',
      'category': '日常消费',
      'iconName': 'shopping_cart',
      'isQuantifiable': 1,
      'unit': '元'
    });
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE members ADD COLUMN gender TEXT DEFAULT "男"');
      await db.execute('ALTER TABLE members ADD COLUMN heightCm REAL DEFAULT 170.0');
      await db.execute('ALTER TABLE members ADD COLUMN weightKg REAL DEFAULT 65.0');
      await db.execute('ALTER TABLE members ADD COLUMN age INTEGER DEFAULT 25');
      await db.execute('ALTER TABLE members ADD COLUMN customStrideCm REAL');
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
}
