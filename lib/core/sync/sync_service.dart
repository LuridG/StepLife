import 'dart:io';
import 'package:path/path.dart' as p;
import '../db/database_service.dart';
import '../cache/cache_manager.dart';
import 'webdav_service.dart';

/// 同步操作结果
class SyncResult {
  final bool success;
  final String message;
  final int uploadedFiles;
  final int downloadedFiles;

  const SyncResult({
    required this.success,
    required this.message,
    this.uploadedFiles = 0,
    this.downloadedFiles = 0,
  });
}

/// WebDAV 手动备份 / 恢复编排
class SyncService {
  /// 备份：DB 快照整体上传 + 图片增量上传（大小不一致即传）
  static Future<SyncResult> backup({
    required String url,
    required String username,
    required String password,
    required String prefix,
    required bool allowSelfSigned,
  }) async {
    try {
      final webdav = WebDavService(
        baseUrl: url,
        username: username,
        password: password,
        prefix: prefix,
        allowSelfSigned: allowSelfSigned,
      );

      await webdav.ensureRemoteDirs();

      // 1) DB 快照
      final dbPath = await DatabaseService.instance.databaseFilePath;
      await DatabaseService.instance.checkpoint();
      final tmpDir = await Directory.systemTemp.createTemp('steplife_sync_');
      final snapshot = p.join(tmpDir.path, 'steplife_v9.db');
      await File(dbPath).copy(snapshot);
      final dbUploaded = await webdav.uploadFile(snapshot, '/db/steplife_v9.db');
      try {
        await tmpDir.delete(recursive: true);
      } catch (_) {}

      // 2) 图片增量
      final imagesDir = await CacheManager.instance.imagesDir();
      final remoteFiles = await webdav.listFiles('/images');
      final remoteMap = {for (final f in remoteFiles) f.path: f.length};

      var uploaded = 0;
      if (await imagesDir.exists()) {
        await for (final entity in imagesDir.list(followLinks: false)) {
          if (entity is! File) continue;
          final name = p.basename(entity.path);
          final localLen = await entity.length();
          if (remoteMap[name] != localLen) {
            final ok = await webdav.uploadFile(entity.path, '/images/$name');
            if (ok) uploaded++;
          }
        }
      }

      final ok = dbUploaded;
      return SyncResult(
        success: ok,
        message: ok
            ? '备份完成：数据库 + ${uploaded.toString()} 张新图片已上传'
            : '备份失败：数据库上传未成功，请检查网络与账号配置',
        uploadedFiles: uploaded + (ok ? 1 : 0),
      );
    } catch (e) {
      return SyncResult(success: false, message: '备份异常: $e');
    }
  }

  /// 恢复：下载远端 DB 替换本地（先备份当前库），再按缺失下载图片
  static Future<SyncResult> restore({
    required String url,
    required String username,
    required String password,
    required String prefix,
    required bool allowSelfSigned,
  }) async {
    try {
      final webdav = WebDavService(
        baseUrl: url,
        username: username,
        password: password,
        prefix: prefix,
        allowSelfSigned: allowSelfSigned,
      );

      final dbPath = await DatabaseService.instance.databaseFilePath;
      final tmpDir = await Directory.systemTemp.createTemp('steplife_restore_');
      final downloaded = p.join(tmpDir.path, 'steplife_v9.db');

      final ok = await webdav.downloadFile('/db/steplife_v9.db', downloaded);
      if (!ok) {
        try {
          await tmpDir.delete(recursive: true);
        } catch (_) {}
        return const SyncResult(
          success: false,
          message: '恢复失败：云端未找到数据库备份，请先执行一次上传',
        );
      }
      final dlLen = await File(downloaded).length();
      if (dlLen < 512) {
        try {
          await tmpDir.delete(recursive: true);
        } catch (_) {}
        return const SyncResult(
          success: false,
          message: '恢复失败：云端数据库文件异常（过小）',
        );
      }

      // 关闭连接 → 备份当前库 → 替换
      await DatabaseService.instance.close();
      final now = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final stamp =
          '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}${two(now.second)}';
      final preBackup = p.join(
        p.dirname(dbPath),
        'steplife_v9_before_restore_$stamp.db',
      );
      if (await File(dbPath).exists()) {
        await File(dbPath).copy(preBackup);
      }
      await File(downloaded).copy(dbPath);
      for (final suffix in ['-wal', '-shm']) {
        final f = File(dbPath + suffix);
        if (await f.exists()) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
      try {
        await tmpDir.delete(recursive: true);
      } catch (_) {}

      // 按缺失下载图片
      final imagesDir = await CacheManager.instance.imagesDir();
      final remoteFiles = await webdav.listFiles('/images');
      var downloadedImages = 0;
      for (final f in remoteFiles) {
        final local = p.join(imagesDir.path, f.path);
        if (!await File(local).exists()) {
          final okImg = await webdav.downloadFile('/images/${f.path}', local);
          if (okImg) downloadedImages++;
        }
      }

      return SyncResult(
        success: true,
        message:
            '恢复完成：数据库已替换（原库已备份），补下载图片 ${downloadedImages.toString()} 张',
        downloadedFiles: 1 + downloadedImages,
      );
    } catch (e) {
      return SyncResult(success: false, message: '恢复异常: $e');
    }
  }
}
