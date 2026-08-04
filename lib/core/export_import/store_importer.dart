import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show getDatabasesPath, DatabaseExecutor;
import '../../features/store_journal/domain/store_models.dart' show MenuItemSpec;
import '../db/database_service.dart';
import 'import_draft.dart';

/// 导入结果统计
class ImportResult {
  const ImportResult({
    required this.createdCategories,
    required this.createdItems,
    required this.createdLogs,
    required this.createdMenus,
    required this.mergedLogs,
    required this.skippedLogs,
  });

  final int createdCategories;
  final int createdItems;
  final int createdLogs;
  final int createdMenus;
  final int mergedLogs;
  final int skippedLogs;

  bool get isEmpty =>
      createdCategories + createdItems + createdLogs + createdMenus + mergedLogs == 0;
}

/// 生活记录导入器：解析/校验 JSON → 草稿；解析归属（新建/合并）；事务落库。
/// 所有操作先进入内存草稿，用户确认后才 apply（自动备份 + 单事务，失败回滚）。
class StoreImporter {
  /// 解析并校验导出 JSON（schemaVersion == 1），返回纯内存草稿。
  static ImportDraft parseJson(String content) {
    Object? decoded;
    try {
      decoded = jsonDecode(content);
    } catch (e) {
      throw FormatException('JSON 解析失败：$e');
    }
    if (decoded is! Map) {
      throw const FormatException('导入文件根节点必须是 JSON 对象');
    }
    final root = Map<String, dynamic>.from(decoded);
    final schemaVersion = root['schemaVersion'];
    if (schemaVersion != 1) {
      throw FormatException('不支持的 schemaVersion：$schemaVersion（当前仅支持 1）');
    }
    if (root['categories'] is! List) {
      throw const FormatException('缺少 categories 数组');
    }
    final catsRaw = root['categories'] as List;
    final cats = <ImportCategoryDraft>[];
    final itemById = <int, ImportItemDraft>{};

    for (var ci = 0; ci < catsRaw.length; ci++) {
      final cr = catsRaw[ci];
      if (cr is! Map) throw FormatException('categories[$ci] 必须是对象');
      final cm = Map<String, dynamic>.from(cr);
      final cName = cm['name']?.toString();
      if (cName == null || cName.trim().isEmpty) {
        throw FormatException('categories[$ci].name 缺失');
      }
      final cat = ImportCategoryDraft(
        name: cName.trim(),
        iconName: cm['iconName']?.toString() ?? 'storefront',
        templateKey: cm['templateKey']?.toString() ?? 'generic',
        extraFields:
            _parseFieldList(cm['extraFieldsJson'], 'categories[$ci].extraFieldsJson'),
      );
      final itemsRaw = cm['items'];
      if (itemsRaw != null) {
        if (itemsRaw is! List) throw FormatException('categories[$ci].items 必须是数组');
        for (var ii = 0; ii < itemsRaw.length; ii++) {
          final ir = itemsRaw[ii];
          if (ir is! Map) throw FormatException('categories[$ci].items[$ii] 必须是对象');
          final im = Map<String, dynamic>.from(ir);
          final iName = im['name']?.toString();
          if (iName == null || iName.trim().isEmpty) {
            throw FormatException('categories[$ci].items[$ii].name 缺失');
          }
          final item = ImportItemDraft(
            name: iName.trim(),
            category: cName.trim(),
            rating: _optNum(im['rating'], 'categories[$ci].items[$ii].rating') ?? 5.0,
            address: im['address']?.toString(),
            notes: im['notes']?.toString(),
            extras: _parseJsonMap(im['extrasJson'], 'categories[$ci].items[$ii].extrasJson'),
            createdAt: _parseTime(im['createdAt'], 'categories[$ci].items[$ii]'),
          );
          final id = im['id'];
          if (id is int) itemById[id] = item;
          cat.items.add(item);
        }
      }
      cats.add(cat);
    }

    final logsRaw = root['logs'];
    if (logsRaw != null) {
      if (logsRaw is! List) throw const FormatException('logs 必须是数组');
      for (var li = 0; li < logsRaw.length; li++) {
        final lr = logsRaw[li];
        if (lr is! Map) throw FormatException('logs[$li] 必须是对象');
        final lm = Map<String, dynamic>.from(lr);
        final sid = lm['storeId'];
        final target = sid is int ? itemById[sid] : null;
        if (target == null) {
          throw FormatException('logs[$li].storeId 未匹配到导入项目（$sid）');
        }
        final names = _parseStringList(lm['visitorNamesJson'], 'logs[$li].visitorNamesJson');
        target.logs.add(ImportLogDraft(
          cost: _optNum(lm['cost'], 'logs[$li].cost'),
          timestamp: _optTime(lm['timestamp'], 'logs[$li]'),
          memo: lm['memo']?.toString(),
          visitorNames: names.isEmpty ? const ['自己'] : names,
          extras: _parseJsonMap(lm['extrasJson'], 'logs[$li].extrasJson'),
          menuNames: _parseStringList(lm['menuNamesJson'], 'logs[$li].menuNamesJson'),
          menuSpecs: _parseStringList(lm['menuSpecsJson'], 'logs[$li].menuSpecsJson'),
        ));
      }
    }

    final menusRaw = root['menuItems'];
    if (menusRaw != null) {
      if (menusRaw is! List) throw const FormatException('menuItems 必须是数组');
      for (var mi = 0; mi < menusRaw.length; mi++) {
        final mr = menusRaw[mi];
        if (mr is! Map) throw FormatException('menuItems[$mi] 必须是对象');
        final mm = Map<String, dynamic>.from(mr);
        final sid = mm['storeId'];
        final target = sid is int ? itemById[sid] : null;
        if (target == null) {
          throw FormatException('menuItems[$mi].storeId 未匹配到导入项目（$sid）');
        }
        target.menuItems.add(ImportMenuItemDraft(
          name: mm['name']?.toString() ?? '',
          price: _optNum(mm['price'], 'menuItems[$mi].price') ?? 0,
          specs: _parseSpecs(mm['specs'], 'menuItems[$mi].specs'),
          rating: (mm['rating'] as num?)?.toInt() ?? 0,
          sortOrder: (mm['sortOrder'] as num?)?.toInt() ?? 0,
        ));
      }
    }

    if (cats.isEmpty) {
      throw const FormatException('导入文件中没有任何分类数据');
    }
    return ImportDraft(categories: cats);
  }

  /// 从「纯打卡」JSON 片段构建草稿：{"logs": [{"cost": 12.5, "timestamp": "2026-07-28 12:30", "memo": "..."}]}，
  /// 归属到指定项目（详情页 L1 纯打卡导入，绝不新建项目）。
  static ImportDraft parseLogsOnly(
    String content, {
    required int targetStoreId,
    required String targetStoreName,
    required String targetCategory,
  }) {
    Object? decoded;
    try {
      decoded = jsonDecode(content);
    } catch (e) {
      throw FormatException('JSON 解析失败：$e');
    }
    if (decoded is! Map) {
      throw const FormatException('文件根节点必须是 JSON 对象');
    }
    final root = Map<String, dynamic>.from(decoded);
    final logsRaw = root['logs'];
    if (logsRaw is! List) {
      throw const FormatException('缺少 logs 数组');
    }
    final cat = ImportCategoryDraft(name: targetCategory);
    cat.strategy = ImportStrategy.merge;
    cat.lockToTarget = targetStoreId != 0;
    final item = ImportItemDraft(name: targetStoreName, category: targetCategory);
    item.strategy = ImportStrategy.merge;
    item.targetItemId = targetStoreId == 0 ? null : targetStoreId;
    item.lockToTarget = targetStoreId != 0;
    for (var li = 0; li < logsRaw.length; li++) {
      final lr = logsRaw[li];
      if (lr is! Map) throw FormatException('logs[$li] 必须是对象');
      final lm = Map<String, dynamic>.from(lr);
      final names = _parseStringList(lm['visitorNamesJson'], 'logs[$li].visitorNamesJson');
      item.logs.add(ImportLogDraft(
        cost: _optNum(lm['cost'], 'logs[$li].cost'),
        timestamp: _optTime(lm['timestamp'], 'logs[$li]'),
        memo: lm['memo']?.toString(),
        visitorNames: names.isEmpty ? const ['自己'] : names,
        extras: _parseJsonMap(lm['extrasJson'], 'logs[$li].extrasJson'),
        menuNames: _parseStringList(lm['menuNamesJson'], 'logs[$li].menuNamesJson'),
        menuSpecs: _parseStringList(lm['menuSpecsJson'], 'logs[$li].menuSpecsJson'),
      ));
    }
    if (item.logs.isEmpty) {
      throw const FormatException('logs 数组中没有任何记录');
    }
    cat.items.add(item);
    return ImportDraft(categories: [cat]);
  }

  /// 依据当前库内数据解析每个分类/项目的归属：同名存在 → 可合并（默认新建）；
  /// 新建且重名 → 名称追加「(导入)」后缀；不存在同名 → 只能新建。
  static Future<void> resolve(ImportDraft draft) async {
    final svc = DatabaseService.instance;
    final categories = await svc.getStoreCategories();
    final items = await svc.getStoreItems();
    final catByName = {for (final c in categories) c.name.trim(): c};
    final itemByKey = {
      for (final i in items) '${i.category.trim()}\u0000${i.name.trim()}': i,
    };

    for (final c in draft.categories) {
      final existingCat = catByName[c.name.trim()];
      if (c.lockToTarget) {
        // 详情页导入：分类锁定为已有分类，绝不新建
        if (existingCat == null) {
          throw FormatException('目标分类「${c.name}」已不存在，无法导入');
        }
        c.targetCategoryId = existingCat.id;
        c.resolvedName = existingCat.name;
        c.strategy = ImportStrategy.merge;
      } else if (existingCat != null) {
        c.targetCategoryId = existingCat.id;
        if (c.strategy == ImportStrategy.create) {
          c.resolvedName = '${c.name} (导入)';
        } else {
          c.resolvedName = existingCat.name;
        }
      } else {
        c.targetCategoryId = null;
        c.resolvedName = c.name;
        c.strategy = ImportStrategy.create;
      }
      for (final it in c.items) {
        it.resolvedCategory = c.resolvedName;
        // 详情页导入：项目锁定为当前餐厅，按 id 定位，定位失败直接报错而不是降级新建
        if (it.lockToTarget) {
          if (it.targetItemId == null) {
            throw FormatException('缺少目标餐厅 ID，无法导入打卡');
          }
          final byId = items.where((i) => i.id == it.targetItemId).toList();
          if (byId.isEmpty) {
            throw FormatException('目标餐厅「${it.name}」已不存在，无法导入');
          }
          it.resolvedName = byId.first.name;
          it.resolvedCategory = byId.first.category;
          it.strategy = ImportStrategy.merge;
          continue;
        }
        // 调用方已显式指定合并目标（账单/纯打卡导入）时按 id 定位，避免名称/分类微差异被误判为新建
        if (it.strategy == ImportStrategy.merge && it.targetItemId != null) {
          final byId = items.where((i) => i.id == it.targetItemId).toList();
          if (byId.isNotEmpty) {
            it.resolvedName = byId.first.name;
            it.resolvedCategory = byId.first.category;
            continue;
          }
          it.targetItemId = null;
        }
        final key = '${it.resolvedCategory.trim()}\u0000${it.name.trim()}';
        final existing = itemByKey[key];
        if (existing != null) {
          it.targetItemId = existing.id;
          if (it.strategy == ImportStrategy.create) {
            it.resolvedName = '${it.name} (导入)';
          } else {
            it.resolvedName = existing.name;
            it.resolvedCategory = existing.category;
          }
        } else {
          it.targetItemId = null;
          it.resolvedName = it.name.trim();
          it.strategy = ImportStrategy.create;
        }
      }
    }
  }

  /// 确认后落库：先 VACUUM INTO 快照备份（保留最近 3 份），再单事务写入。
  static Future<ImportResult> apply(ImportDraft draft) async {
    final svc = DatabaseService.instance;
    final dbDir = await getDatabasesPath();
    final stamp = _stamp();
    final backupPath = p.join(dbDir, 'steplife_import_backup_$stamp.db');
    await svc.vacuumInto(backupPath);
    await _trimImportBackups(dbDir);

    final db = await svc.database;
    var createdCategories = 0;
    var createdItems = 0;
    var createdLogs = 0;
    var createdMenus = 0;
    var mergedLogs = 0;
    var skippedLogs = 0;

    await db.transaction((txn) async {
      // 按 项目+秒 索引已有打卡，用于「合并」时同一秒增补而非新建
      final existingLogsBySecond = <int, Map<String, Map<String, dynamic>>>{};
      final allLogs = await txn.query('store_logs');
      for (final row in allLogs) {
        final sid = row['storeId'] as int?;
        final tsRaw = row['timestamp'] as String?;
        if (sid == null || tsRaw == null) continue;
        final tsDt = _parseTsLoose(tsRaw);
        if (tsDt == null) continue;
        (existingLogsBySecond[sid] ??= <String, Map<String, dynamic>>{})[_secondKey(tsDt)] = row;
      }
      for (final c in draft.categories) {
        if (!c.selected) continue;
        var catId = c.targetCategoryId;
        if (c.lockToTarget) {
          // 详情页导入：分类必须已存在，禁止新建
          if (catId == null) {
            throw const FormatException('目标分类已不存在，无法导入');
          }
          final catRow = await txn.query('store_categories',
              where: 'id = ?', whereArgs: [catId]);
          if (catRow.isEmpty) {
            throw const FormatException('目标分类已不存在，无法导入');
          }
        } else if (c.strategy == ImportStrategy.create || catId == null) {
          // 新建分类防撞名：同名已存在时追加 (导入N) 后缀，避免 UNIQUE 冲突
          var catName = c.resolvedName;
          var suffix = 2;
          while (true) {
            final dup = await txn.query('store_categories',
                where: 'name = ?', whereArgs: [catName]);
            if (dup.isEmpty) break;
            catName = '${c.resolvedName} (导入$suffix)';
            suffix++;
          }
          if (catName != c.resolvedName) {
            c.resolvedName = catName;
            for (final it in c.items) {
              it.resolvedCategory = catName;
            }
          }
          catId = await txn.insert('store_categories', {
            'name': c.resolvedName,
            'iconName': c.iconName,
            'templateKey': c.templateKey,
            'extraFieldsJson': jsonEncode(c.extraFields),
          });
          createdCategories++;
        }
        final menuKeys = <int, Set<String>>{};
        for (final it in c.items) {
          if (!it.selected) continue;
          var itemId = it.targetItemId;
          final itemLocked = it.lockToTarget;
          final isCreated =
              !itemLocked && (it.strategy == ImportStrategy.create || itemId == null);
          if (itemLocked) {
            // 详情页导入：餐厅必须已存在，禁止新建
            if (itemId == null) {
              throw const FormatException('缺少目标餐厅 ID，无法导入打卡');
            }
            final itemRow = await txn.query('store_items',
                where: 'id = ?', whereArgs: [itemId]);
            if (itemRow.isEmpty) {
              throw const FormatException('目标餐厅已不存在，无法导入打卡');
            }
          } else if (isCreated) {
            // 新建项目防撞名：同分类下同名已存在时追加 (导入N) 后缀
            var itemName = it.resolvedName;
            var suffix = 2;
            while (true) {
              final dup = await txn.query('store_items',
                  where: 'category = ? AND name = ?',
                  whereArgs: [c.resolvedName, itemName]);
              if (dup.isEmpty) break;
              itemName = '${it.resolvedName} (导入$suffix)';
              suffix++;
            }
            it.resolvedName = itemName;
            itemId = await txn.insert('store_items', {
              'name': it.resolvedName,
              'category': c.resolvedName,
              'rating': it.rating,
              'imagesJson': '[]',
              'address': it.address,
              'notes': it.notes,
              'extrasJson': jsonEncode(it.extras),
              'createdAt': it.createdAt.toIso8601String(),
            });
            createdItems++;
          }
          final safeItemId = itemId!;
          final keys = menuKeys.putIfAbsent(safeItemId, () => <String>{});
          for (final m in it.menuItems) {
            if (!m.selected) continue;
            final specJson = jsonEncode(m.specs.map((s) => s.toJson()).toList());
            final key = jsonEncode([m.name, specJson]);
            if (!keys.add(key)) continue;
            await txn.insert('store_menu_items', {
              'storeId': safeItemId,
              'name': m.name,
              'price': m.price,
              'imagePath': null,
              'specsJson': specJson,
              'rating': m.rating,
              'sortOrder': m.sortOrder,
              'createdAt': DateTime.now().toIso8601String(),
            });
            createdMenus++;
          }
          for (final l in it.logs) {
            if (!l.selected) {
              skippedLogs++;
              continue;
            }
            final ts = l.timestamp;
            if (ts == null) {
              throw const FormatException('存在缺少时间的打卡记录，请在预览中补充时间后再导入');
            }
            if (!isCreated && l.strategy == ImportStrategy.merge) {
              // 合并：同一秒已有打卡 → 在原记录上增补缺失字段；否则追加新打卡
              final existing = existingLogsBySecond[safeItemId]?[_secondKey(ts)];
              if (existing != null) {
                await _mergeIntoLog(txn, existing, l);
                mergedLogs++;
                continue;
              }
            }
            await txn.insert('store_logs', {
              'storeId': safeItemId,
              'storeName': it.resolvedName,
              'cost': l.cost,
              'visitorIdsJson': '[]',
              'visitorNamesJson':
                  jsonEncode(l.visitorNames.isEmpty ? const ['自己'] : l.visitorNames),
              'memo': l.memo,
              'extrasJson': jsonEncode(l.extras),
              'menuItemIdsJson': '[]',
              'menuNamesJson': jsonEncode(l.menuNames),
              'menuSpecsJson': jsonEncode(l.menuSpecs),
              'timestamp': _secondPrecision(ts).toIso8601String(),
            });
            createdLogs++;
          }
        }
      }
    });

    return ImportResult(
      createdCategories: createdCategories,
      createdItems: createdItems,
      createdLogs: createdLogs,
      createdMenus: createdMenus,
      mergedLogs: mergedLogs,
      skippedLogs: skippedLogs,
    );
  }

  // ---------- 内部工具 ----------

  static String _stamp() {
    return DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
  }

  static Future<void> _trimImportBackups(String dbDir) async {
    try {
      final dir = Directory(dbDir);
      final backups = await dir
          .list()
          .where(
            (e) =>
                e is File &&
                p.basename(e.path).startsWith('steplife_import_backup_') &&
                p.basename(e.path).endsWith('.db'),
          )
          .cast<File>()
          .toList();
      backups.sort((a, b) => b.path.compareTo(a.path));
      for (final old in backups.skip(3)) {
        try {
          await old.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  static double? _optNum(Object? raw, String where) {
    if (raw == null) return null;
    final n = raw is num ? raw.toDouble() : double.tryParse(raw.toString());
    if (n == null) throw FormatException('$where 不是数字');
    return n;
  }

  static DateTime? _optTime(Object? raw, String where) {
    if (raw == null || raw.toString().trim().isEmpty) return null;
    final s = raw.toString().trim();
    DateTime? dt;
    for (final fmt in ['yyyy-MM-dd HH:mm:ss', 'yyyy-MM-dd HH:mm']) {
      try {
        dt = DateFormat(fmt).parse(s);
        break;
      } catch (_) {}
    }
    dt ??= DateTime.tryParse(s);
    if (dt == null) {
      throw FormatException('$where 时间格式非法：$s（需要 yyyy-MM-dd HH:mm:ss）');
    }
    return _secondPrecision(dt);
  }

  static DateTime? _parseTsLoose(String s) {
    final t = DateTime.tryParse(s.trim());
    if (t != null) return _secondPrecision(t);
    for (final fmt in ['yyyy-MM-dd HH:mm:ss', 'yyyy-MM-dd HH:mm']) {
      try {
        return _secondPrecision(DateFormat(fmt).parse(s.trim()));
      } catch (_) {}
    }
    return null;
  }

  static DateTime _secondPrecision(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second);

  static String _secondKey(DateTime dt) =>
      DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(dt);

  static Future<void> _mergeIntoLog(
    DatabaseExecutor txn,
    Map<String, dynamic> row,
    ImportLogDraft l,
  ) async {
    final cost = row['cost'] ?? l.cost;
    var memo = row['memo'] as String?;
    if ((memo == null || memo.isEmpty) && (l.memo?.trim().isNotEmpty ?? false)) {
      memo = l.memo;
    }
    var visitorNames = _decodeStrListSafe(row['visitorNamesJson']);
    if (visitorNames.isEmpty && l.visitorNames.isNotEmpty) {
      visitorNames = l.visitorNames;
    }
    var menuNames = _decodeStrListSafe(row['menuNamesJson']);
    if (menuNames.isEmpty && l.menuNames.isNotEmpty) {
      menuNames = l.menuNames;
    }
    var menuSpecs = _decodeStrListSafe(row['menuSpecsJson']);
    if (menuSpecs.isEmpty && l.menuSpecs.isNotEmpty) {
      menuSpecs = l.menuSpecs;
    }
    final extras = _mergeExtras(_decodeJsonMapSafe(row['extrasJson']), l.extras);
    await txn.update(
      'store_logs',
      {
        'cost': cost,
        'visitorNamesJson':
            jsonEncode(visitorNames.isEmpty ? const ['自己'] : visitorNames),
        'memo': memo,
        'extrasJson': jsonEncode(extras),
        'menuNamesJson': jsonEncode(menuNames),
        'menuSpecsJson': jsonEncode(menuSpecs),
      },
      where: 'id = ?',
      whereArgs: [row['id']],
    );
  }

  static List<String> _decodeStrListSafe(Object? raw) {
    if (raw == null) return const [];
    try {
      final d = jsonDecode(raw.toString());
      if (d is List) return d.map((e) => e.toString()).toList();
    } catch (_) {}
    return const [];
  }

  static Map<String, dynamic> _decodeJsonMapSafe(Object? raw) {
    if (raw == null) return {};
    try {
      final d = jsonDecode(raw.toString());
      if (d is Map) return Map<String, dynamic>.from(d);
    } catch (_) {}
    return {};
  }

  static Map<String, dynamic> _mergeExtras(
    Map<String, dynamic> base,
    Map<String, dynamic> add,
  ) {
    final out = Map<String, dynamic>.from(base);
    add.forEach((k, v) => out.putIfAbsent(k, () => v));
    return out;
  }

  static DateTime _parseTime(Object? raw, String where) {
    if (raw == null || raw.toString().trim().isEmpty) return DateTime.now();
    final s = raw.toString().trim();
    try {
      return DateFormat('yyyy-MM-dd HH:mm').parse(s);
    } catch (_) {}
    final dt = DateTime.tryParse(s);
    if (dt == null) {
      throw FormatException('$where 时间格式非法：$s（需要 yyyy-MM-dd HH:mm）');
    }
    return dt;
  }

  static Map<String, dynamic> _parseJsonMap(Object? raw, String where) {
    if (raw == null) return {};
    try {
      final d = jsonDecode(raw.toString());
      if (d is Map) return Map<String, dynamic>.from(d);
    } catch (_) {}
    throw FormatException('$where 格式非法（应为 JSON 对象）');
  }

  static List<Map<String, dynamic>> _parseFieldList(Object? raw, String where) {
    if (raw == null) return [];
    try {
      final d = jsonDecode(raw.toString());
      if (d is List) {
        return d
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    throw FormatException('$where 格式非法（应为 JSON 数组）');
  }

  static List<String> _parseStringList(Object? raw, String where) {
    if (raw == null) return [];
    try {
      final d = jsonDecode(raw.toString());
      if (d is List) return d.map((e) => e.toString()).toList();
    } catch (_) {}
    throw FormatException('$where 格式非法（应为 JSON 数组）');
  }

  static List<MenuItemSpec> _parseSpecs(Object? raw, String where) {
    if (raw == null) return [];
    try {
      final d = jsonDecode(raw.toString());
      if (d is List) {
        return d
            .whereType<Map>()
            .map((e) => MenuItemSpec.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    throw FormatException('$where 格式非法（应为 JSON 数组）');
  }
}
