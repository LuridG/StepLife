import 'package:flutter/foundation.dart';
import '../db/database_service.dart';

/// 全局设置状态（app_settings 表读写封装）
class SettingsProvider extends ChangeNotifier {
  // 主题模式: dark / light / system
  String _themeMode = 'dark';
  // 生活 Tab 默认视图: card / list
  String _preferredViewMode = 'card';
  // 缓存上限 MB，0 = 不限
  int _cacheLimitMB = 0;
  // 新选图压缩质量: 60 / 75 / 85
  int _imageQuality = 75;
  // TMDB API Key（留空 = 不启用）
  String _tmdbApiKey = '';
  // DeepSeek API Key（智能助手，留空 = 禁用）
  String _deepseekApiKey = '';
  // WebDAV 配置
  String _webdavUrl = '';
  String _webdavUsername = '';
  String _webdavPassword = '';
  String _webdavPrefix = '/steplife';
  bool _webdavAllowSelfSigned = false;
  String _webdavLastSync = '';
  // 打卡默认成员: self / last
  String _defaultMember = 'self';
  // 上次打卡使用成员 ID（逗号分隔），defaultMember=last 时使用
  String _lastCheckinMemberIds = '';
  // 上次备份状态提示（如备份失败）
  String _backupWarning = '';
  // 启动时自动检查更新（仅 Android）
  bool _autoCheckUpdate = true;
  // 生活记录分类筛选栏模式: expanded 展开显示 / collapsed 隐藏为悬浮按钮
  String _storeFilterBarMode = 'expanded';
  // 生活记录默认筛选分类（'全部分类' 或某一分类名，下次启动生效）
  String _storeDefaultFilterCategory = '全部分类';
  // 悬浮筛选按钮常态透明度（0.2 ~ 1.0，用户可调）
  double _storeFilterFabOpacity = 0.5;
  bool _loaded = false;

  String get themeMode => _themeMode;
  String get preferredViewMode => _preferredViewMode;
  int get cacheLimitMB => _cacheLimitMB;
  int get imageQuality => _imageQuality;
  String get tmdbApiKey => _tmdbApiKey;
  String get deepseekApiKey => _deepseekApiKey;
  String get webdavUrl => _webdavUrl;
  String get webdavUsername => _webdavUsername;
  String get webdavPassword => _webdavPassword;
  String get webdavPrefix => _webdavPrefix;
  bool get webdavAllowSelfSigned => _webdavAllowSelfSigned;
  String get webdavLastSync => _webdavLastSync;
  String get defaultMember => _defaultMember;
  String get lastCheckinMemberIds => _lastCheckinMemberIds;
  String get backupWarning => _backupWarning;
  bool get loaded => _loaded;
  bool get tmdbEnabled => _tmdbApiKey.trim().isNotEmpty;
  bool get webdavConfigured =>
      _webdavUrl.trim().isNotEmpty && _webdavUsername.trim().isNotEmpty;
  bool get autoCheckUpdate => _autoCheckUpdate;
  String get storeFilterBarMode => _storeFilterBarMode;
  String get storeDefaultFilterCategory => _storeDefaultFilterCategory;
  double get storeFilterFabOpacity => _storeFilterFabOpacity;

  static const String kThemeMode = 'theme_mode';
  static const String kPreferredViewMode = 'preferredViewMode';
  static const String kCacheLimitMB = 'cache_limit_mb';
  static const String kImageQuality = 'image_quality';
  static const String kTmdbApiKey = 'tmdb_api_key';
  static const String kDeepseekApiKey = 'deepseek_api_key';
  static const String kWebdavUrl = 'webdav_url';
  static const String kWebdavUsername = 'webdav_username';
  static const String kWebdavPassword = 'webdav_password';
  static const String kWebdavPrefix = 'webdav_prefix';
  static const String kWebdavAllowSelfSigned = 'webdav_allow_self_signed';
  static const String kWebdavLastSync = 'webdav_last_sync';
  static const String kDefaultMember = 'default_member';
  static const String kLastCheckinMemberIds = 'last_checkin_member_ids';
  static const String kBackupWarning = 'backup_warning';
  static const String kAutoCheckUpdate = 'auto_check_update';
  static const String kStoreFilterBarMode = 'store_filter_bar_mode';
  static const String kStoreDefaultFilterCategory = 'store_default_filter_category';
  static const String kStoreFilterFabOpacity = 'store_filter_fab_opacity';
  static const String kRouteSort = 'route_sort';

  /// 从 app_settings 加载全部设置
  Future<void> load() async {
    try {
      final all = await DatabaseService.instance.getAllSettings();
      _themeMode = all[kThemeMode] ?? 'dark';
      _preferredViewMode = all[kPreferredViewMode] ?? 'card';
      _cacheLimitMB = int.tryParse(all[kCacheLimitMB] ?? '') ?? 0;
      _imageQuality = int.tryParse(all[kImageQuality] ?? '') ?? 75;
      _tmdbApiKey = all[kTmdbApiKey] ?? '';
      _deepseekApiKey = all[kDeepseekApiKey] ?? '';
      _webdavUrl = all[kWebdavUrl] ?? '';
      _webdavUsername = all[kWebdavUsername] ?? '';
      _webdavPassword = all[kWebdavPassword] ?? '';
      _webdavPrefix = all[kWebdavPrefix] ?? '/steplife';
      _webdavAllowSelfSigned = all[kWebdavAllowSelfSigned] == 'true';
      _webdavLastSync = all[kWebdavLastSync] ?? '';
      _defaultMember = all[kDefaultMember] ?? 'self';
      _lastCheckinMemberIds = all[kLastCheckinMemberIds] ?? '';
      _backupWarning = all[kBackupWarning] ?? '';
      _autoCheckUpdate = all[kAutoCheckUpdate] != 'false';
      _storeFilterBarMode = all[kStoreFilterBarMode] ?? 'expanded';
      _storeDefaultFilterCategory = all[kStoreDefaultFilterCategory] ?? '全部分类';
      _storeFilterFabOpacity = double.tryParse(all[kStoreFilterFabOpacity] ?? '') ?? 0.5;
      _loaded = true;
      notifyListeners();
    } catch (_) {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> _save(String key, String value) async {
    await DatabaseService.instance.setSetting(key, value);
  }

  Future<void> setThemeMode(String mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    await _save(kThemeMode, mode);
  }

  Future<void> setPreferredViewMode(String mode) async {
    _preferredViewMode = mode;
    notifyListeners();
    await DatabaseService.instance.savePreferredViewMode(mode);
  }

  Future<void> setCacheLimitMB(int mb) async {
    _cacheLimitMB = mb;
    notifyListeners();
    await _save(kCacheLimitMB, mb.toString());
  }

  Future<void> setImageQuality(int q) async {
    _imageQuality = q;
    notifyListeners();
    await _save(kImageQuality, q.toString());
  }

  Future<void> setTmdbApiKey(String key) async {
    _tmdbApiKey = key.trim();
    notifyListeners();
    await _save(kTmdbApiKey, _tmdbApiKey);
  }

  Future<void> setDeepseekApiKey(String key) async {
    _deepseekApiKey = key.trim();
    notifyListeners();
    await _save(kDeepseekApiKey, _deepseekApiKey);
  }

  Future<void> setWebdavConfig({
    required String url,
    required String username,
    required String password,
    required String prefix,
    required bool allowSelfSigned,
  }) async {
    _webdavUrl = url.trim();
    _webdavUsername = username.trim();
    _webdavPassword = password;
    _webdavPrefix = prefix.trim().isEmpty ? '/steplife' : prefix.trim();
    _webdavAllowSelfSigned = allowSelfSigned;
    notifyListeners();
    await _save(kWebdavUrl, _webdavUrl);
    await _save(kWebdavUsername, _webdavUsername);
    await _save(kWebdavPassword, _webdavPassword);
    await _save(kWebdavPrefix, _webdavPrefix);
    await _save(kWebdavAllowSelfSigned, allowSelfSigned.toString());
  }

  Future<void> setWebdavLastSync(String timeStr) async {
    _webdavLastSync = timeStr;
    notifyListeners();
    await _save(kWebdavLastSync, timeStr);
  }

  Future<void> setDefaultMember(String mode) async {
    _defaultMember = mode;
    notifyListeners();
    await _save(kDefaultMember, mode);
  }

  Future<void> setLastCheckinMemberIds(String ids) async {
    _lastCheckinMemberIds = ids;
    await _save(kLastCheckinMemberIds, ids);
  }

  Future<void> setBackupWarning(String message) async {
    _backupWarning = message;
    notifyListeners();
    await _save(kBackupWarning, message);
  }

  Future<void> setAutoCheckUpdate(bool value) async {
    _autoCheckUpdate = value;
    notifyListeners();
    await _save(kAutoCheckUpdate, value.toString());
  }

  Future<void> setStoreFilterBarMode(String mode) async {
    if (_storeFilterBarMode == mode) return;
    _storeFilterBarMode = mode;
    notifyListeners();
    await _save(kStoreFilterBarMode, mode);
  }

  Future<void> setStoreDefaultFilterCategory(String name) async {
    if (_storeDefaultFilterCategory == name) return;
    _storeDefaultFilterCategory = name;
    notifyListeners();
    await _save(kStoreDefaultFilterCategory, name);
  }

  Future<void> setStoreFilterFabOpacity(double opacity) async {
    final v = opacity.clamp(0.2, 1.0);
    if (_storeFilterFabOpacity == v) return;
    _storeFilterFabOpacity = v;
    notifyListeners();
    await _save(kStoreFilterFabOpacity, v.toString());
  }
}
