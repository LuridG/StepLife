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
  final Map<String, int>? counts;

  const SyncResult({
    required this.success,
    required this.message,
    this.uploadedFiles = 0,
    this.downloadedFiles = 0,
    this.counts,
  });
}

/// WebDAV 手动备份 / 恢复编排
class SyncService {
  /// 备份：DB 一致性快照整体上传（VACUUM INTO，失败回退 checkpoint+复制）+ 图片增量上传
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

      // 1) DB 一致性快照：优先 VACUUM INTO（WAL 安全），失败回退 checkpoint + 复制
      final dbPath = await DatabaseService.instance.databaseFilePath;
      final tmpDir = await Directory.systemTemp.createTemp('steplife_sync_');
      final snapshot = p.join(tmpDir.path, 'steplife_v9.db');
      var snapshotOk = false;
      try {
        await DatabaseService.instance.vacuumInto(snapshot);
        snapshotOk = await File(snapshot).exists() &&
            (await File(snapshot).length()) > 0;
      } catch (_) {}
      if (!snapshotOk) {
        await DatabaseService.instance.checkpoint();
        await File(dbPath).copy(snapshot);
      }

      // 校验快照完整性并统计各表行数（路线/家务/生活记录全覆盖）
      final verify = await DatabaseService.instance.verifySnapshot(snapshot);
      final counts =
          Map<String, int>.from((verify['counts'] as Map?) ?? const {});
      final dbUploaded = await webdav.uploadFile(snapshot, '/db/steplife_v9.db');
      try {
        await tmpDir.delete(recursive: true);
      } catch (_) {}

      // 2) 图片增量上传（按文件名 + 大小去重）
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

      // 3) TMDB 海报缓存增量上传
      final tmdbDir = await CacheManager.instance.tmdbDir();
      final remoteTmdb = await webdav.listFiles('/tmdb');
      final remoteTmdbMap = {for (final f in remoteTmdb) f.path: f.length};
      var uploadedTmdb = 0;
      if (await tmdbDir.exists()) {
        await for (final entity in tmdbDir.list(followLinks: false)) {
          if (entity is! File) continue;
          final name = p.basename(entity.path);
          final localLen = await entity.length();
          if (remoteTmdbMap[name] != localLen) {
            final ok = await webdav.uploadFile(entity.path, '/tmdb/$name');
            if (ok) uploadedTmdb++;
          }
        }
      }

      final ok = dbUploaded && verify['ok'] == true;
      return SyncResult(
        success: ok,
        message: ok
            ? '备份完成：数据库校验通过（${_countsSummary(counts)}），新图片 $uploaded 张、海报 $uploadedTmdb 张已上传'
            : '备份失败：数据库上传未成功或完整性校验未通过，请检查网络与账号配置',
        uploadedFiles: uploaded + uploadedTmdb + (ok ? 1 : 0),
      );
    } catch (e) {
      return SyncResult(success: false, message: '备份失败：${_friendlyError(e)}');
    }
  }

  /// 恢复：下载远端 DB 先校验，再替换本地（先备份当前库），重映射图片路径，按缺失补下载图片
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

      // 先用只读方式校验云端库完整性 + 统计行数
      final verify = await DatabaseService.instance.verifySnapshot(downloaded);
      final counts =
          Map<String, int>.from((verify['counts'] as Map?) ?? const {});
      if (verify['ok'] != true) {
        try {
          await tmpDir.delete(recursive: true);
        } catch (_) {}
        return const SyncResult(
          success: false,
          message: '恢复失败：云端数据库完整性校验未通过，请重新执行一次上传',
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

      // 重新打开新库（触发幂等 onOpen 补表），并重映射图片路径到当前缓存目录
      await DatabaseService.instance.database;
      final relinked =
          await DatabaseService.instance.relinkImagesAfterRestore();

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

      // 按缺失下载 TMDB 海报
      final tmdbDir = await CacheManager.instance.tmdbDir();
      final remoteTmdb = await webdav.listFiles('/tmdb');
      var downloadedTmdb = 0;
      for (final f in remoteTmdb) {
        final local = p.join(tmdbDir.path, f.path);
        if (!await File(local).exists()) {
          final ok = await webdav.downloadFile('/tmdb/${f.path}', local);
          if (ok) downloadedTmdb++;
        }
      }

      return SyncResult(
        success: true,
        message:
            '恢复完成：${_countsSummary(counts)}；图片重映射 $relinked 张、补下载图片 $downloadedImages 张、海报 $downloadedTmdb 张（原库已备份为 steplife_v9_before_restore_*.db）',
        downloadedFiles: 1 + downloadedImages + downloadedTmdb,
      );
    } catch (e) {
      return SyncResult(success: false, message: '恢复失败：${_friendlyError(e)}');
    }
  }

  /// 远端备份文件信息（大小 + 上传时间），只查不下载
  static Future<SyncResult> remoteBackupInfo({
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
      final info = await webdav.fileInfo('/db/steplife_v9.db');
      if (info == null) {
        return const SyncResult(
          success: false,
          message: '远端未找到数据库备份，请先执行一次「立即上传」',
        );
      }
      return SyncResult(
        success: true,
        message: '远端数据库备份：${_fmtSize(info.length)}，上传时间 ${info.mtime ?? '未知'}',
      );
    } catch (e) {
      return SyncResult(success: false, message: '查询失败：${_friendlyError(e)}');
    }
  }

  /// 校验远端备份：下载数据库做完整性校验 + 各表行数统计（不替换本地数据）
  static Future<SyncResult> inspectRemoteBackup({
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
      final tmpDir = await Directory.systemTemp.createTemp('steplife_inspect_');
      final downloaded = p.join(tmpDir.path, 'steplife_v9.db');
      final ok = await webdav.downloadFile('/db/steplife_v9.db', downloaded);
      if (!ok) {
        try {
          await tmpDir.delete(recursive: true);
        } catch (_) {}
        return const SyncResult(
          success: false,
          message: '远端未找到数据库备份，请先执行一次「立即上传」',
        );
      }
      final verify = await DatabaseService.instance.verifySnapshot(downloaded);
      try {
        await tmpDir.delete(recursive: true);
      } catch (_) {}
      final counts =
          Map<String, int>.from((verify['counts'] as Map?) ?? const {});
      if (verify['ok'] != true) {
        return SyncResult(
          success: false,
          message: '校验未通过：云端数据库完整性异常，请重新执行一次「立即上传」',
          counts: counts,
        );
      }
      return SyncResult(
        success: true,
        message: '校验通过：数据库完整，${_countsSummary(counts)}',
        counts: counts,
      );
    } catch (e) {
      return SyncResult(success: false, message: '校验失败：${_friendlyError(e)}');
    }
  }

  static String _fmtSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  static String _countsSummary(Map<String, int> c) {
    int n(String key) => c[key] ?? 0;
    return '路线${n('routes')}条/路线测量${n('route_measurements')}条/行走打卡${n('step_logs')}条/家务${n('chore_items')}项/家务打卡${n('chore_logs')}条/生活记录${n('store_items')}条/成员${n('members')}人';
  }

  /// 将底层网络异常翻译为可操作的中文提示
  static String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('SocketException') ||
        s.contains('Connection refused') ||
        s.contains('Connection closed') ||
        s.contains('Failed host lookup')) {
      return '无法连接 WebDAV 服务器，请检查：① 服务器（NAS/DUFS/坚果云等）是否已启动；② 手机与服务器是否在同一局域网；③ 地址与端口是否填写正确';
    }
    if (s.contains('TimeoutException') || s.contains('timed out')) {
      return '连接 WebDAV 服务器超时，请检查网络或稍后重试';
    }
    if (s.contains('401') || s.contains('403') || s.contains('Unauthorized')) {
      return 'WebDAV 认证失败，请检查用户名与密码';
    }
    if (s.contains('404') || s.contains('Not Found')) {
      return '远端路径不存在，请先执行一次「立即上传」';
    }
    if (s.contains('HandshakeException') || s.contains('certificate')) {
      return 'SSL 证书校验失败，可尝试在设置中开启「允许自签名证书」';
    }
    return '操作异常: $e';
  }
}
