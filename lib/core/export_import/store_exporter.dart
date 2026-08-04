import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../db/database_service.dart';

/// 生活记录数据导出器（JSON v1 Schema）。
/// 支持单分类 / 全量两种粒度；图片本期不导出，保留 images 字段位，
/// 为将来 zip 带图方案预留 includeImages 钩子。
class StoreExporter {
  static const int schemaVersion = 1;

  /// 构建导出数据（内存对象，不落盘、不写库）。
  /// [category] 为空表示全量导出；否则仅导出该分类及其项目/打卡/菜单。
  static Future<Map<String, dynamic>> buildExportData({String? category}) async {
    final db = DatabaseService.instance;
    final categories = await db.getStoreCategories();
    final items = await db.getStoreItems();
    final logs = await db.getStoreLogs();
    final menuItems = await db.getStoreMenuItems();

    final fmt = DateFormat('yyyy-MM-dd HH:mm');

    final scopedCategories = <String>{};
    final categoryList = <Map<String, dynamic>>[];
    for (final c in categories) {
      if (category != null && c.name != category) continue;
      scopedCategories.add(c.name);
      categoryList.add({
        'id': c.id,
        'name': c.name,
        'iconName': c.iconName,
        'templateKey': c.templateKey,
        'extraFieldsJson': jsonEncode(c.extraFields),
      });
    }

    final scopedItemIds = <int>{};
    final itemList = <Map<String, dynamic>>[];
    for (final it in items) {
      if (!scopedCategories.contains(it.category)) continue;
      if (it.id != null) scopedItemIds.add(it.id!);
      itemList.add({
        'id': it.id,
        'name': it.name,
        'category': it.category,
        'rating': it.rating,
        'images': const <String>[], // 图片字段位：本期恒空
        'address': it.address,
        'notes': it.notes,
        'extrasJson': jsonEncode(it.extras),
        'createdAt': fmt.format(it.createdAt),
      });
    }

    final logList = <Map<String, dynamic>>[];
    for (final l in logs) {
      if (!scopedItemIds.contains(l.storeId)) continue;
      logList.add({
        'id': l.id,
        'storeId': l.storeId,
        'storeName': l.storeName,
        'cost': l.cost,
        'visitorIdsJson': jsonEncode(l.visitorIds),
        'visitorNamesJson': jsonEncode(l.visitorNames),
        'memo': l.memo,
        'extrasJson': jsonEncode(l.extras),
        'menuItemIdsJson': jsonEncode(l.menuItemIds),
        'menuNamesJson': jsonEncode(l.menuNames),
        'menuSpecsJson': jsonEncode(l.menuSpecs),
        'timestamp': fmt.format(l.timestamp),
      });
    }

    final menuList = <Map<String, dynamic>>[];
    for (final m in menuItems) {
      if (!scopedItemIds.contains(m.storeId)) continue;
      menuList.add({
        'id': m.id,
        'storeId': m.storeId,
        'name': m.name,
        'price': m.price,
        'imagePath': null, // 图片不导出
        'specs': m.specs.map((s) => s.toJson()).toList(),
        'rating': m.rating,
        'sortOrder': m.sortOrder,
      });
    }

    String appVersion = '';
    try {
      appVersion = (await PackageInfo.fromPlatform()).version;
    } catch (_) {}

    return {
      'schemaVersion': schemaVersion,
      'exportType': category == null ? 'full' : 'category',
      'sourceAppVersion': appVersion,
      'exportedAt': fmt.format(DateTime.now()),
      'categories': categoryList,
      'items': itemList,
      'logs': logList,
      'menuItems': menuList,
    };
}

  /// 写出 JSON 到应用缓存目录并返回文件。
  static Future<File> writeExportFile(
    Map<String, dynamic> data, {
    String? category,
  }) async {
    final dir = await getApplicationCacheDirectory();
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final base = category == null
        ? 'steplife_store_export_all'
        : 'steplife_store_category_${_safeName(category)}';
    final file = File(p.join(dir.path, '${base}_$stamp.json'));
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(data), encoding: utf8);
    return file;
  }

  /// 复制到应用文档目录留底，返回目标文件。
  static Future<File> copyToDocuments(File src) async {
    final dir = await getApplicationDocumentsDirectory();
    final target = File(p.join(dir.path, p.basename(src.path)));
    await target.writeAsBytes(await src.readAsBytes(), flush: true);
    return target;
  }

  /// 调用系统分享面板分享文件（桌面端无面板时返回 false）。
  static Future<bool> shareFile(File file) async {
    try {
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        subject: 'StepLife 生活记录导出',
        text: 'StepLife 生活记录导出数据（JSON）',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  static String _safeName(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }
}
