import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../cache/cache_manager.dart';
import '../sync/sync_service.dart';
import '../db/database_service.dart';
import 'settings_provider.dart';

/// 设置中心：外观 / 模板与分类 / WebDAV 同步 / 缓存管理 / 关于
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  CacheStats? _cacheStats;
  bool _syncing = false;
  bool _restoring = false;
  final TextEditingController _tmdbKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tmdbKeyController.text = context.read<SettingsProvider>().tmdbApiKey;
    _refreshCacheStats();
  }

  @override
  void dispose() {
    _tmdbKeyController.dispose();
    super.dispose();
  }

  Future<void> _refreshCacheStats() async {
    final stats = await CacheManager.instance.stats();
    if (mounted) setState(() => _cacheStats = stats);
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.redAccent : const Color(0xFF10B981),
      ),
    );
  }

  Future<void> _showWebdavConfigDialog() async {
    final settings = context.read<SettingsProvider>();
    final urlC = TextEditingController(text: settings.webdavUrl);
    final userC = TextEditingController(text: settings.webdavUsername);
    final passC = TextEditingController(text: settings.webdavPassword);
    final prefixC = TextEditingController(text: settings.webdavPrefix);
    var allowSelfSigned = settings.webdavAllowSelfSigned;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('WebDAV 服务器配置'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: urlC,
                  decoration: const InputDecoration(
                    labelText: '服务器地址',
                    hintText: '例: https://dav.jianguoyun.com/dav',
                    prefixIcon: Icon(Icons.dns_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: userC,
                  decoration: const InputDecoration(
                    labelText: '账号',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passC,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '密码 / 应用密码',
                    prefixIcon: Icon(Icons.lock_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: prefixC,
                  decoration: const InputDecoration(
                    labelText: '远程路径前缀',
                    hintText: '/steplife',
                    prefixIcon: Icon(Icons.folder_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('允许自签名 TLS 证书', style: TextStyle(fontSize: 13)),
                  value: allowSelfSigned,
                  onChanged: (v) => setModalState(() => allowSelfSigned = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                await settings.setWebdavConfig(
                  url: urlC.text,
                  username: userC.text,
                  password: passC.text,
                  prefix: prefixC.text,
                  allowSelfSigned: allowSelfSigned,
                );
                if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                _toast('WebDAV 配置已保存');
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _backupNow() async {
    final settings = context.read<SettingsProvider>();
    if (!settings.webdavConfigured) {
      _toast('请先配置 WebDAV 服务器', error: true);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('上传备份到 WebDAV?'),
        content: const Text('将上传数据库快照与新增图片，远端仅追加不删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
            child: const Text('开始上传'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _syncing = true);
    final result = await SyncService.backup(
      url: settings.webdavUrl,
      username: settings.webdavUsername,
      password: settings.webdavPassword,
      prefix: settings.webdavPrefix,
      allowSelfSigned: settings.webdavAllowSelfSigned,
    );
    if (mounted) setState(() => _syncing = false);
    if (result.success) {
      await settings.setWebdavLastSync(
        DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
      );
      _toast(result.message);
    } else {
      _toast(result.message, error: true);
    }
  }

  Future<void> _restoreNow() async {
    final settings = context.read<SettingsProvider>();
    if (!settings.webdavConfigured) {
      _toast('请先配置 WebDAV 服务器', error: true);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从云端恢复?'),
        content: const Text('将用云端数据库替换本地数据（本地当前库会先自动备份），图片按缺失补下载。此操作不可撤销，建议先手动上传一次最新备份。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('确认恢复', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _restoring = true);
    final result = await SyncService.restore(
      url: settings.webdavUrl,
      username: settings.webdavUsername,
      password: settings.webdavPassword,
      prefix: settings.webdavPrefix,
      allowSelfSigned: settings.webdavAllowSelfSigned,
    );
    if (mounted) setState(() => _restoring = false);
    if (result.success) {
      _toast(result.message);
    } else {
      _toast(result.message, error: true);
    }
  }

  Future<void> _resetTemplateBindings() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复内置模板绑定?'),
        content: const Text('将按分类名称重新智能匹配模板（电影→影视、小店→餐饮等），自定义字段保留。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final updated = await DatabaseService.instance.resetTemplateBindings();
    _toast('已恢复 ${updated.toString()} 个分类的模板绑定');
  }

  Future<void> _cleanCacheNow() async {
    final settings = context.read<SettingsProvider>();
    final removed = await CacheManager.instance.clean(limitMB: settings.cacheLimitMB);
    await _refreshCacheStats();
    _toast('已清理缓存文件 ${removed.toString()} 个');
  }

  Widget _section(String title, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(16),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withAlpha(35), width: 1.2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF10B981),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 12),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _segmented<T>({
    required Set<T> selected,
    required List<ButtonSegment<T>> segments,
    required void Function(Set<T>) onChanged,
  }) {
    return SegmentedButton<T>(
      segments: segments,
      selected: selected,
      onSelectionChanged: onChanged,
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? Colors.white : Colors.white70),
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? const Color(0xFF10B981).withAlpha(200)
                : Colors.white.withAlpha(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('设置中心')),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF090D16), Color(0xFF111C38), Color(0xFF0F172A)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // 外观与偏好
                _section('外观与偏好', Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('主题模式', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 8),
                    _segmented<String>(
                      selected: {settings.themeMode},
                      segments: const [
                        ButtonSegment(value: 'dark', label: Text('深色'), icon: Icon(Icons.dark_mode_outlined, size: 16)),
                        ButtonSegment(value: 'light', label: Text('浅色'), icon: Icon(Icons.light_mode_outlined, size: 16)),
                        ButtonSegment(value: 'system', label: Text('跟随系统'), icon: Icon(Icons.settings_brightness, size: 16)),
                      ],
                      onChanged: (v) => settings.setThemeMode(v.first),
                    ),
                    const SizedBox(height: 16),
                    const Text('生活默认视图', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 8),
                    _segmented<String>(
                      selected: {settings.preferredViewMode},
                      segments: const [
                        ButtonSegment(value: 'card', label: Text('卡片'), icon: Icon(Icons.grid_view, size: 16)),
                        ButtonSegment(value: 'list', label: Text('紧凑列表'), icon: Icon(Icons.view_headline, size: 16)),
                      ],
                      onChanged: (v) => settings.setPreferredViewMode(v.first),
                    ),
                    const SizedBox(height: 16),
                    const Text('打卡默认成员', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 8),
                    _segmented<String>(
                      selected: {settings.defaultMember},
                      segments: const [
                        ButtonSegment(value: 'self', label: Text('自己'), icon: Icon(Icons.person_outline, size: 16)),
                        ButtonSegment(value: 'last', label: Text('上次使用'), icon: Icon(Icons.history, size: 16)),
                      ],
                      onChanged: (v) => settings.setDefaultMember(v.first),
                    ),
                    const SizedBox(height: 10),
                    const Text('页面背景保留品牌深色渐变，主题切换影响对话框与系统控件', style: TextStyle(fontSize: 11, color: Colors.white38)),
                  ],
                )),

                // 模板与分类
                _section('模板与分类', Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('TMDB API Key（影视模板搜索，留空 = 离线）', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _tmdbKeyController,
                      obscureText: true,
                      decoration: InputDecoration(
                        hintText: '粘贴 v3 API Key 或 v4 Read Access Token (eyJ...)',
                        prefixIcon: const Icon(Icons.movie_filter_outlined),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.save_outlined, size: 20),
                          onPressed: () {
                            settings.setTmdbApiKey(_tmdbKeyController.text);
                            _toast('TMDB Key 已保存');
                          },
                        ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _resetTemplateBindings,
                            icon: const Icon(Icons.restore, size: 18),
                            label: const Text('恢复内置模板绑定'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('数据来源 TMDB（themoviedb.org）。可填 v3 API Key（32 位）或 v4 Read Access Token（eyJ 开头），两者都支持', style: TextStyle(fontSize: 11, color: Colors.white38)),
                  ],
                )),

                // WebDAV 同步
                _section('数据与同步（WebDAV）', Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.cloud_outlined, color: Color(0xFF10B981)),
                      title: const Text('服务器配置', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                      subtitle: Text(
                        settings.webdavConfigured
                            ? settings.webdavUrl
                            : '未配置（支持坚果云 / Nextcloud / NAS）',
                        style: TextStyle(fontSize: 12, color: settings.webdavConfigured ? Colors.white70 : Colors.white38),
                      ),
                      trailing: TextButton(
                        onPressed: _showWebdavConfigDialog,
                        child: const Text('编辑'),
                      ),
                    ),
                    const Divider(height: 8, color: Colors.white12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _syncing ? null : _backupNow,
                            icon: _syncing
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.upload_outlined, size: 18),
                            label: const Text('立即上传'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _restoring ? null : _restoreNow,
                            icon: _restoring
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.download_outlined, size: 18),
                            label: const Text('立即恢复'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      settings.webdavLastSync.isEmpty
                          ? '尚未同步过'
                          : '上次同步: ${settings.webdavLastSync}',
                      style: const TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                    const SizedBox(height: 4),
                    const Text('账号密码 v1 明文存本地 SQLite，请谨慎保管；恢复操作会先自动备份本地库', style: TextStyle(fontSize: 11, color: Colors.white38)),
                  ],
                )),

                // 缓存管理
                _section('缓存管理', Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _statTile('图片', _cacheStats?.imagesMb ?? '…', Icons.image_outlined),
                        ),
                        Expanded(
                          child: _statTile('TMDB 海报', _cacheStats?.tmdbMb ?? '…', Icons.movie_outlined),
                        ),
                        Expanded(
                          child: _statTile('数据库', _cacheStats?.dbMb ?? '…', Icons.storage_outlined),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '当前总计: ${_cacheStats?.totalMb ?? '…'} MB（含图片缓存与数据库）',
                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                    const SizedBox(height: 14),
                    const Text('缓存上限', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 8),
                    _segmented<int>(
                      selected: {settings.cacheLimitMB},
                      segments: const [
                        ButtonSegment(value: 0, label: Text('不限')),
                        ButtonSegment(value: 50, label: Text('50MB')),
                        ButtonSegment(value: 100, label: Text('100MB')),
                        ButtonSegment(value: 200, label: Text('200MB')),
                        ButtonSegment(value: 500, label: Text('500MB')),
                      ],
                      onChanged: (v) => settings.setCacheLimitMB(v.first),
                    ),
                    const SizedBox(height: 16),
                    const Text('新图片压缩质量', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 8),
                    _segmented<int>(
                      selected: {settings.imageQuality},
                      segments: const [
                        ButtonSegment(value: 60, label: Text('60')),
                        ButtonSegment(value: 75, label: Text('75')),
                        ButtonSegment(value: 85, label: Text('85')),
                      ],
                      onChanged: (v) => settings.setImageQuality(v.first),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _cleanCacheNow,
                            icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                            label: const Text('按上限清理'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              await CacheManager.instance.clearImages();
                              await _refreshCacheStats();
                              _toast('缓存图片已清空');
                            },
                            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                            label: const Text('一键清空'),
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text('旧图不受质量设置影响，仅影响新选图压缩', style: TextStyle(fontSize: 11, color: Colors.white38)),
                  ],
                )),

                // 关于
                _section('关于', Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.info_outline, color: Color(0xFF06B6D4)),
                      title: Text('StepLife 步履生活', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                      subtitle: Text('v1.4.5+20260807 · 数据来源 TMDB', style: TextStyle(fontSize: 12, color: Colors.white54)),
                    ),
                    const SizedBox(height: 4),
                    if (settings.backupWarning.isNotEmpty)
                      Text('提示: ${settings.backupWarning}', style: const TextStyle(fontSize: 12, color: Colors.orangeAccent)),
                  ],
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statTile(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFF06B6D4), size: 20),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.white54)),
      ],
    );
  }
}
