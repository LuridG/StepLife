import 'dart:io';
import '../db/database_service.dart';
import 'cache_manager.dart';

/// 图片惰性迁移：把旧条目引用相册的原路径图片，
/// 后台复制进应用缓存目录并逐条更新（幂等、可中断、失败跳过）。
class ImageMigrator {
  static const String _doneKey = 'image_migration_v1_done';

  /// 启动后延迟执行，不阻塞首屏
  static void schedule() {
    Future.delayed(const Duration(seconds: 2), run);
  }

  static Future<void> run() async {
    try {
      final done = await DatabaseService.instance.getSetting(_doneKey);
      if (done == 'true') return;

      final items = await DatabaseService.instance.getStoreItems();
      final imagesDir = await CacheManager.instance.imagesDir();
      var migrated = 0;

      for (final item in items) {
        if (item.images.isEmpty) continue;
        final newImages = <String>[];
        var changed = false;
        for (final img in item.images) {
          if (img.startsWith(imagesDir.path)) {
            newImages.add(img);
            continue;
          }
          final f = File(img);
          if (await f.exists()) {
            try {
              final dest = await CacheManager.instance.copyToCache(img);
              newImages.add(dest);
              changed = true;
              migrated++;
            } catch (_) {
              newImages.add(img);
            }
          } else {
            // 原文件已不存在：保留原路径，展示层容错
            newImages.add(img);
          }
        }
        if (changed) {
          await DatabaseService.instance
              .updateStoreItem(item.copyWith(images: newImages));
        }
      }

      await DatabaseService.instance.setSetting(_doneKey, 'true');
      // 迁移统计留痕
      await DatabaseService.instance
          .setSetting('image_migration_stats', migrated.toString());
    } catch (_) {
      // 惰性迁移失败不影响主流程
    }
  }
}
