import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show getDatabasesPath;
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
          timestamp: _parseTime(lm['timestamp'], 'logs[$li]'),
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
    final item = ImportItemDraft(name: targetStoreName, category: targetCategory);
    item.strategy = ImportStrategy.merge;
    item.targetItemId = targetStoreId == 0 ? null : targetStoreId;
    for (var li = 0; li < logsRaw.length; li++) {
      final lr = logsRaw[li];
      if (lr is! Map) throw FormatException('logs[$li] 必须是对象');
      final lm = Map<String, dynamic>.from(lr);
      final names = _parseStringList(lm['visitorNamesJson'], 'logs[$li].visitorNamesJson');
      item.logs.add(ImportLogDraft(
        cost: _optNum(lm['cost'], 'logs[$li].cost'),
        timestamp: _parseTime(lm['timestamp'], 'logs[$li]'),
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
    final catByName = {for (final c in categories) c.name: c};
    final itemByKey = {
      for (final i in items) '${i.category}\u0000${i.name}': i,
    };

    for (final c in draft.categories) {
      final existingCat = catByName[c.name];
      if (existingCat != null) {
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
        final key = '${it.resolvedCategory}\u0000${it.name}';
        final existing = itemByKey[key];
        if (existing != null) {
          it.targetItemId = existing.id;
          if (it.strategy == ImportStrategy.create) {
            it.resolvedName = '${it.name} (导入)';
          } else {
            it.resolvedName = existing.name;
          }
        } else {
          it.targetItemId = null;
          it.resolvedName = it.name;
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
      for (final c in draft.categories) {
        if (!c.selected) continue;
        var catId = c.targetCategoryId;
        if (c.strategy == ImportStrategy.create || catId == null) {
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
          final isCreated = it.strategy == ImportStrategy.create || itemId == null;
          if (isCreated) {
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
          final keys = menuKeys.putIfAbsent(itemId, () => <String>{});
          for (final m in it.menuItems) {
            if (!m.selected) continue;
            final specJson = jsonEncode(m.specs.map((s) => s.toJson()).toList());
            final key = jsonEncode([m.name, specJson]);
            if (!keys.add(key)) continue;
            await txn.insert('store_menu_items', {
              'storeId': itemId,
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
            await txn.insert('store_logs', {
              'storeId': itemId,
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
              'timestamp': l.timestamp.toIso8601String(),
            });
            if (isCreated) {
              createdLogs++;
            } else {
              mergedLogs++;
            }
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
