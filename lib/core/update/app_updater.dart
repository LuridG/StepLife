import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// GitHub Release 信息（用于应用内自动更新）
class UpdateInfo {
  final String version; // 新版本号（去掉 v 前缀，含 build 号，如 1.4.15+20260817）
  final String tagName; // 如 v1.4.15+20260817
  final String notes; // 更新说明（Release body）
  final String apkUrl; // 对应架构 APK 下载地址
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

  /// 更新检查源：直连 api.github.com 在国内常被拒，按顺序回退到加速镜像
  static const List<String> _checkEndpoints = [
    _repoApi,
    'https://ghproxy.net/$_repoApi',
    'https://gh-proxy.com/$_repoApi',
    'https://ghfast.top/$_repoApi',
    'https://mirror.ghproxy.com/$_repoApi',
  ];

  /// APK 下载加速镜像（直链失败时按顺序回退）
  static const List<String> _mirrorHosts = [
    'https://ghproxy.net',
    'https://gh-proxy.com',
    'https://ghfast.top',
  ];

  static const MethodChannel _channel = MethodChannel('steplife/updater');
  static const String _apkFileName = 'StepLife-update.apk';

  /// 当前安装版本（version + buildNumber）
  static Future<PackageInfo> packageInfo() => PackageInfo.fromPlatform();

  /// 检查 GitHub 最新 Release；无新版本返回 null。
  /// 全部更新源均失败时抛出异常，由调用方决定是否提示。
  static Future<UpdateInfo?> checkForUpdate() async {
    Object? lastError;
    for (final endpoint in _checkEndpoints) {
      try {
        return await _fetchLatest(endpoint);
      } catch (e) {
        lastError = e;
      }
    }
    throw HttpException(
      '已尝试 ${_checkEndpoints.length} 个更新源均不可用，请检查网络后重试 ($lastError)',
    );
  }

  static Future<UpdateInfo?> _fetchLatest(String endpoint) async {
    final resp = await http
        .get(Uri.parse(endpoint), headers: const {'User-Agent': 'StepLife'})
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw HttpException('HTTP ${resp.statusCode}');
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

  /// 下载 APK 到应用缓存目录；直链失败时依次回退加速镜像
  static Future<File> downloadApk(
    UpdateInfo info,
    void Function(int received, int total) onProgress, {
    bool Function()? isCancelled,
  }) async {
    final dir = await getApplicationCacheDirectory();
    final file = File('${dir.path}/$_apkFileName');
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
    final urls = _expandDownloadUrls(info.apkUrl);
    Object? lastError;
    for (final url in urls) {
      try {
        await _downloadTo(file, url, onProgress, isCancelled);
        return file;
      } catch (e) {
        lastError = e;
        // 清理半成品，准备用下一个源重试
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }
    throw HttpException(
      '已尝试 ${urls.length} 个下载源均不可用，请检查网络后重试 ($lastError)',
    );
  }

  /// 生成下载地址列表：直链 + 镜像前缀
  static List<String> _expandDownloadUrls(String url) {
    if (!url.startsWith('https://github.com/')) return [url];
    return [
      url,
      for (final host in _mirrorHosts) '$host/$url',
    ];
  }

  static Future<void> _downloadTo(
    File file,
    String url,
    void Function(int received, int total) onProgress,
    bool Function()? isCancelled,
  ) async {
    final request = http.Request('GET', Uri.parse(url));
    final resp = await http.Client()
        .send(request)
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      throw HttpException('HTTP ${resp.statusCode}');
    }
    final total = resp.contentLength ?? 0;
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
    } finally {
      await sink.close();
    }
  }

  /// 拉起系统安装器安装 APK；返回 false 表示需要先授权「安装未知应用」
  static Future<bool> installApk(File file) async {
    final ok = await _channel.invokeMethod<bool>('installApk', {'path': file.path});
    return ok ?? false;
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
      final dir = await getApplicationCacheDirectory();
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
