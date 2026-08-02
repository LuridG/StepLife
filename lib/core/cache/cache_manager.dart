import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 缓存统计结果
class CacheStats {
  final int imagesBytes;
  final int tmdbBytes;
  final int dbBytes;
  final int totalBytes;

  const CacheStats({
    this.imagesBytes = 0,
    this.tmdbBytes = 0,
    this.dbBytes = 0,
  }) : totalBytes = imagesBytes + tmdbBytes + dbBytes;

  String get totalMb => (totalBytes / (1024 * 1024)).toStringAsFixed(1);
  String get imagesMb => (imagesBytes / (1024 * 1024)).toStringAsFixed(1);
  String get tmdbMb => (tmdbBytes / (1024 * 1024)).toStringAsFixed(1);
  String get dbMb => (dbBytes / (1024 * 1024)).toStringAsFixed(1);
}

/// 缓存管理：选图复制进应用目录、统计、按上限清理
class CacheManager {
  static final CacheManager instance = CacheManager._internal();
  CacheManager._internal();

  Future<Directory> _ensureDir(String sub) async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, sub));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> imagesDir() => _ensureDir(p.join('cache', 'images'));
  Future<Directory> tmdbDir() => _ensureDir(p.join('cache', 'tmdb'));

  /// 把选图/海报复制进应用缓存目录，返回新路径
  Future<String> copyToCache(String sourcePath, {bool tmdb = false}) async {
    final dir = tmdb ? await tmdbDir() : await imagesDir();
    final ext = p.extension(sourcePath);
    final name =
        'img_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}$ext';
    final dest = p.join(dir.path, name);
    await File(sourcePath).copy(dest);
    return dest;
  }

  Future<CacheStats> stats() async {
    Future<int> folderSize(Directory dir) async {
      if (!await dir.exists()) return 0;
      var total = 0;
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
      return total;
    }

    final images = await folderSize(await imagesDir());
    final tmdb = await folderSize(await tmdbDir());
    int dbBytes = 0;
    try {
      final support = await getApplicationSupportDirectory();
      final dbFile = File(p.join(support.path, 'db', 'steplife_v9.db'));
      if (await dbFile.exists()) {
        dbBytes = await dbFile.length();
      }
    } catch (_) {}
    return CacheStats(imagesBytes: images, tmdbBytes: tmdb, dbBytes: dbBytes);
  }

  /// 按 mtime 从旧到新删除，直到降至上限 80%（返回删除的文件数）
  Future<int> clean({int? limitMB}) async {
    if (limitMB == null || limitMB <= 0) return 0;
    var stats = await this.stats();
    final limitBytes = limitMB * 1024 * 1024;
    final targetBytes = (limitBytes * 0.8).round();
    if (stats.totalBytes <= targetBytes) return 0;

    final files = <File>[];
    for (final dir in [await imagesDir(), await tmdbDir()]) {
      if (!await dir.exists()) continue;
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File) files.add(e);
      }
    }
    // 预读 mtime 后排序（旧 → 新）
    final withTime = <MapEntry<File, DateTime>>[];
    for (final f in files) {
      try {
        withTime.add(MapEntry(f, await f.lastModified()));
      } catch (_) {}
    }
    withTime.sort((a, b) => a.value.compareTo(b.value));

    var removed = 0;
    var remaining = stats.totalBytes;
    for (final entry in withTime) {
      if (remaining <= targetBytes) break;
      final len = await entry.key.length();
      try {
        await entry.key.delete();
        remaining -= len;
        removed++;
      } catch (_) {}
    }
    return removed;
  }

  /// 写入新图前检查上限，超限先触发清理
  Future<void> enforceLimitBeforeWrite(int limitMB) async {
    if (limitMB <= 0) return;
    final stats = await this.stats();
    if (stats.totalBytes >= limitMB * 1024 * 1024) {
      await clean(limitMB: limitMB);
    }
  }

  /// 一键清空缓存图片（不动数据库）
  Future<void> clearImages() async {
    for (final dir in [await imagesDir(), await tmdbDir()]) {
      if (!await dir.exists()) continue;
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        try {
          if (e is File) await e.delete();
        } catch (_) {}
      }
    }
  }
}
