import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// GitHub Release 信息（用于应用内自动更新）
class UpdateInfo {
  final String version; // 新版本号（去掉 v 前缀，含 build 号，如 1.4.8+20260810）
  final String tagName; // 如 v1.4.8+20260810
  final String notes; // 更新说明（Release body）
  final String apkUrl; // universal APK 下载地址
  final int apkSize; // APK 大小（字节），未知为 0

  const UpdateInfo({
    required this.version,
    required this.tagName,
    required this.notes,
    required this.apkUrl,
    required this.apkSize,
  });

  String get versionName => version.split('+').first;
}

/// 应用内自动更新：检查 GitHub Release、下载 APK、拉起系统安装器
class AppUpdater {
  static const String _repoApi =
      'https://api.github.com/repos/LuridG/StepLife/releases/latest';
  static const MethodChannel _channel = MethodChannel('steplife/updater');
  static const String _apkFileName = 'StepLife-update.apk';

  /// 当前安装版本（version + buildNumber）
  static Future<PackageInfo> packageInfo() => PackageInfo.fromPlatform();

  /// 检查 GitHub 最新 Release；无新版本返回 null。
  /// 网络或解析失败会抛出异常，由调用方决定是否提示。
  static Future<UpdateInfo?> checkForUpdate() async {
    final resp = await http
        .get(Uri.parse(_repoApi), headers: const {'User-Agent': 'StepLife'})
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) {
      throw HttpException('检查更新失败: HTTP ${resp.statusCode}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final tag = (json['tag_name'] as String? ?? '').trim();
    if (tag.isEmpty) return null;
    final notes = (json['body'] as String? ?? '').trim();
    final assets = (json['assets'] as List?) ?? const [];
    // 按设备 ABI 选择对应架构安装包（arm64-v8a / armeabi-v7a / x86_64），无法识别时回退 universal
    final abi = await deviceAbi();
    final apkAsset = _pickApkAsset(assets, abi);
    final url = apkAsset['browser_download_url'] as String?;
    if (url == null || url.isEmpty) return null;

    final info = await PackageInfo.fromPlatform();
    final remote = tag.replaceFirst(RegExp(r'^[vV]'), '');
    final current = '${info.version}+${info.buildNumber}';
    if (!_isNewer(remote, current)) return null;

    return UpdateInfo(
      version: remote,
      tagName: tag,
      notes: notes,
      apkUrl: url,
      apkSize: (apkAsset['size'] as num?)?.toInt() ?? 0,
    );
  }

  /// 当前设备主 ABI（如 arm64-v8a / armeabi-v7a / x86_64）；获取失败返回空串
  static Future<String> deviceAbi() async {
    try {
      final v = await _channel.invokeMethod<String>('getAbi');
      return v?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  /// 根据设备 ABI 匹配 Release 资产中的 APK；无法识别时回退 universal
  static Map<String, dynamic> _pickApkAsset(
      List<dynamic> assets, String abi) {
    final key = abi.toLowerCase();
    String? wantedSuffix;
    if (key.contains('arm64') || key.contains('aarch64')) {
      wantedSuffix = '-arm64-v8a.apk';
    } else if (key.contains('armeabi') || key.contains('armv')) {
      wantedSuffix = '-armeabi-v7a.apk';
    } else if (key.contains('x86_64') || key.contains('amd64')) {
      wantedSuffix = '-x86_64.apk';
    }
    Map<String, dynamic>? fallback;
    for (final a in assets) {
      if (a is! Map) continue;
      final name = (a['name'] as String? ?? '');
      if (wantedSuffix != null && name.endsWith(wantedSuffix)) {
        return Map<String, dynamic>.from(a);
      }
      if (name.endsWith('-universal.apk')) {
        fallback = Map<String, dynamic>.from(a);
      }
    }
    return fallback ?? const {};
  }

  /// 静默检查（启动自动检查用）：任何失败都返回 null，不打扰用户
  static Future<UpdateInfo?> safeCheckForUpdate() async {
    try {
      return await checkForUpdate();
    } catch (_) {
      return null;
    }
  }

  /// 下载 APK 到应用文档目录，进度回调 (received, total)
  static Future<File> downloadApk(
    UpdateInfo info,
    void Function(int received, int total) onProgress, {
    bool Function()? isCancelled,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$_apkFileName');
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
    final request = http.Request('GET', Uri.parse(info.apkUrl));
    final resp = await http.Client().send(request);
    if (resp.statusCode != 200) {
      throw HttpException('下载失败: HTTP ${resp.statusCode}');
    }
    final total = resp.contentLength ?? info.apkSize;
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in resp.stream) {
        if (isCancelled?.call() ?? false) {
          throw HttpException('下载已取消');
        }
        received += chunk.length;
        sink.add(chunk);
        if (total > 0) onProgress(received, total);
      }
    } catch (_) {
      // 下载失败/取消：清理残留文件，避免占用缓存
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      rethrow;
    } finally {
      await sink.close();
    }
    return file;
  }

  /// 拉起系统安装器安装 APK
  static Future<void> installApk(File file) async {
    await _channel.invokeMethod('installApk', {'path': file.path});
  }

  /// 删除已下载的安装包（更新完成后清理）
  static Future<void> deleteApk(File file) async {
    try {
      await _channel.invokeMethod('deleteApk', {'path': file.path});
    } catch (_) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  /// 清理残留安装包（应用启动时调用，更新完成后下次启动自动删除）
  static Future<void> cleanupStaleApk() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_apkFileName');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  /// 版本比较：remote > current 返回 true
  static bool _isNewer(String remote, String current) {
    final r = _parse(remote);
    final c = _parse(current);
    for (var i = 0; i < r.length; i++) {
      if (r[i] != c[i]) return r[i] > c[i];
    }
    return false;
  }

  static List<int> _parse(String v) {
    final plus = v.indexOf('+');
    final base = plus >= 0 ? v.substring(0, plus) : v;
    final build = plus >= 0 ? int.tryParse(v.substring(plus + 1)) ?? 0 : 0;
    final parts = base.split('.');
    final nums = <int>[];
    for (var i = 0; i < 3; i++) {
      nums.add(i < parts.length ? int.tryParse(parts[i]) ?? 0 : 0);
    }
    nums.add(build);
    return nums;
  }
}
