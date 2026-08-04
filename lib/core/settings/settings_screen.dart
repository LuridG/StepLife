import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../cache/cache_manager.dart';
import '../sync/sync_service.dart';
import '../db/database_service.dart';
import '../update/app_updater.dart';
import '../update/update_dialog.dart';
import 'settings_provider.dart';
import '../export_import/bill_parser.dart';
import '../../features/step_tracker/providers/step_provider.dart';
import '../../features/chore_tracker/providers/chore_provider.dart';
import '../../features/store_journal/providers/store_provider.dart';
import '../../features/profile/providers/profile_provider.dart';

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
  bool _inspecting = false;
  bool _checkingUpdate = false;
  String _appVersion = '';
  final TextEditingController _tmdbKeyController = TextEditingController();
  final TextEditingController _deepseekKeyController = TextEditingController();
  final TextEditingController _sensitiveKwCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tmdbKeyController.text = context.read<SettingsProvider>().tmdbApiKey;
    _deepseekKeyController.text = context.read<SettingsProvider>().deepseekApiKey;
    _sensitiveKwCtrl.text = context.read<SettingsProvider>().billSensitiveKeywords.join('\n');
    _refreshCacheStats();
    _loadAppVersion();
  }

  @override
  void dispose() {
    _tmdbKeyController.dispose();
    _deepseekKeyController.dispose();
    _sensitiveKwCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshCacheStats() async {
    final stats = await CacheManager.instance.stats();
    if (mounted) setState(() => _cacheStats = stats);
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await AppUpdater.packageInfo();
      if (mounted) setState(() => _appVersion = '${info.version}+${info.buildNumber}');
    } catch (_) {}
  }

  Future<void> _checkUpdateNow() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    try {
      final info = await AppUpdater.checkForUpdate();
      if (!mounted) return;
      if (info == null) {
        _toast(_appVersion.isEmpty ? '已是最新版本' : '已是最新版本 v$_appVersion');
      } else {
        await showUpdateDialog(context, info);
      }
    } catch (e) {
      if (!mounted) return;
      _toast('检查更新失败: $e', error: true);
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
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

  void _saveSensitiveKeywords() {
    final keywords = _sensitiveKwCtrl.text
        .split(RegExp(r'[\n,，、;；]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    context.read<SettingsProvider>().setBillSensitiveKeywords(keywords);
    _toast('敏感词已保存');
  }

  void _resetSensitiveKeywords() {
    _sensitiveKwCtrl.text = BillParser.defaultSensitiveKeywords.join('\n');
    context.read<SettingsProvider>().setBillSensitiveKeywords(
          List.of(BillParser.defaultSensitiveKeywords),
        );
    _toast('已恢复默认敏感词');
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
      if (mounted) {
        // 恢复后强制重载全部数据源，避免界面停留在旧内存数据上
        context.read<SettingsProvider>().load();
        context.read<StepProvider>().loadData();
        context.read<ChoreProvider>().loadData();
        context.read<StoreProvider>().loadData();
        context.read<ProfileProvider>().loadProfile();
        _refreshCacheStats();
      }
      _toast(result.message);
    } else {
      _toast(result.message, error: true);
    }
  }

  Future<void> _verifyRemote() async {
    final settings = context.read<SettingsProvider>();
    if (!settings.webdavConfigured) {
      _toast('请先配置 WebDAV 服务器', error: true);
      return;
    }
    setState(() => _inspecting = true);
    final result = await SyncService.inspectRemoteBackup(
      url: settings.webdavUrl,
      username: settings.webdavUsername,
      password: settings.webdavPassword,
      prefix: settings.webdavPrefix,
      allowSelfSigned: settings.webdavAllowSelfSigned,
    );
    if (mounted) setState(() => _inspecting = false);
    _showInspectDialog(result.success ? '远端校验通过' : '远端校验未通过', result);
  }

  Future<void> _analyzeRemote() async {
    final settings = context.read<SettingsProvider>();
    if (!settings.webdavConfigured) {
      _toast('请先配置 WebDAV 服务器', error: true);
      return;
    }
    setState(() => _inspecting = true);
    final result = await SyncService.inspectRemoteBackup(
      url: settings.webdavUrl,
      username: settings.webdavUsername,
      password: settings.webdavPassword,
      prefix: settings.webdavPrefix,
      allowSelfSigned: settings.webdavAllowSelfSigned,
    );
    if (mounted) setState(() => _inspecting = false);
    _showInspectDialog('远端备份数据概览', result);
  }

  Future<void> _remoteInfo() async {
    final settings = context.read<SettingsProvider>();
    if (!settings.webdavConfigured) {
      _toast('请先配置 WebDAV 服务器', error: true);
      return;
    }
    setState(() => _inspecting = true);
    final result = await SyncService.remoteBackupInfo(
      url: settings.webdavUrl,
      username: settings.webdavUsername,
      password: settings.webdavPassword,
      prefix: settings.webdavPrefix,
      allowSelfSigned: settings.webdavAllowSelfSigned,
    );
    if (mounted) setState(() => _inspecting = false);
    _toast(result.message, error: !result.success);
  }

  void _showInspectDialog(String title, SyncResult result) {
    if (!mounted) return;
    const labels = <String, String>{
      'routes': '路线',
      'step_logs': '行走打卡',
      'members': '成员',
      'chore_items': '家务项目',
      'chore_logs': '家务打卡',
      'store_categories': '生活分类',
      'store_items': '生活记录',
      'store_logs': '生活打卡',
      'store_menu_items': '菜品菜单',
      'user_profile': '个人档案',
    };
    final counts = result.counts;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      result.success ? Icons.check_circle : Icons.error,
                      color: result.success ? const Color(0xFF10B981) : Colors.redAccent,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(result.message,
                          style: const TextStyle(fontSize: 13, color: Colors.white70)),
                    ),
                  ],
                ),
                if (counts != null) ...[
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white12, height: 1),
                  const SizedBox(height: 8),
                  for (final entry in labels.entries)
                    if ((counts[entry.key] ?? 0) > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(entry.value,
                                style: const TextStyle(fontSize: 13, color: Colors.white70)),
                            Text('${counts[entry.key]} 条',
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white)),
                          ],
                        ),
                      ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('关闭')),
        ],
      ),
    );
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

  /// 关于：更新记录与版本历史弹窗
  void _showChangelogDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.history_toggle_off, color: Color(0xFF6366F1)),
            SizedBox(width: 8),
            Text('更新记录与版本历史'),
          ],
        ),
        content: SizedBox(
          width: 540,
          height: 440,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildVersionItem(
                  version: 'v1.6.3 (2026-08-23)',
                  isLatest: true,
                  changes: [
                    '🔧 修复账单 OCR 导入闪退：中文识别模型未打包（ML Kit 仅内置拉丁文），补充 text-recognition-chinese 依赖，离线模型随 APK 打包，OCR 全离线可用。',
                  ],
                ),
                const Divider(color: Colors.white12, height: 24),
                _buildVersionItem(
                  version: 'v1.6.2 (2026-08-22)',
                  isLatest: false,
                  changes: [
                    '🧹 家务界面优化：打卡时刻选择器改圆角卡片；5 天日期矩阵自适应缩放防溢出，日期圈 38→31dp；标题按长度自适应字号，量化数值与备注角标展示。',
                    '📱 生活记录打卡时刻选择器同步圆角卡片；分类抽屉超长分类名省略号截断。',
                    '👤 成员卡片重构：头像+姓名+编辑/删除按钮同行紧凑排布，信息区收进圆角描边容器。',
                    '🎨 底部 Tab 栏字号与点击反馈优化（亮/暗主题一致）；助手确认卡片意图文本自动换行。',
                  ],
                ),
                const Divider(color: Colors.white12, height: 24),
                _buildVersionItem(
                  version: 'v1.6.1 (2026-08-21)',
                  isLatest: false,
                  changes: [
                    '📥 生活记录导入导出：单分类/全量 JSON 导出（图片字段预留、share 分享）；模板化导入与模拟导入（dry-run 预览可勾选/编辑/切换策略）；账单 OCR+AI 批量导入（一张图多笔消费）。',
                    '🔒 导入防误建与合并：详情页导入锁定当前餐厅/分类禁止误建；合并按同项目+同一秒匹配只增补不重复，逐条/批量切换新建或合并，缺时间禁止落库。',
                    '🕵️ OCR 敏感词脱敏：默认过滤交易单号/商户单号等敏感词，可自定义；脱敏后人工复核再送 AI。',
                    '📊 打卡历史增强：卡片/紧凑视图一键切换，时间与金额多条件叠加筛选，统计按模板类型差异化展示（菜篮子沿用原图表）。',
                  ],
                ),
                const Divider(color: Colors.white12, height: 24),
                _buildVersionItem(
                  version: 'v1.6.0 (2026-08-20)',
                  isLatest: false,
                  changes: [
                    '🧹 家务事项支持编辑与删除：卡片 ⋮ 菜单可改名称/分类/量化单位，删除时连同全部打卡记录一并清理。',
                    '📦 生活记录顶栏收纳：设置/排序/视图切换收进「⋮ 更多」下拉，只留新建打卡，标题不再被按钮挤没。',
                    '🔀 排序图标化：时间/星级/打卡次数改为图标菜单项，支持顺序/逆序切换（点当前项翻转方向，逐分类记住偏好）。',
                    '🎤 修复安卓语音输入：补麦克风权限申请与引导、错误码中文提示、中文语音包缺失时回退系统默认语言。',
                    '🧠 助手模板动态化：提示词随内置模板自动生成，新增模板无需手动同步。',
                    '✂️ 文案精简：路线页、打卡详情、家务等界面短文案去冗余（路线库 / 打卡记录 / 步量方圆生活等）。',
                  ],
                ),
                const Divider(color: Colors.white12, height: 24),
                _buildVersionItem(
                  version: 'v1.5.0 (2026-08-19)',
                  isLatest: false,
                  changes: [
                    '🤖 智能助手（DeepSeek v4-flash）：家务/生活页左上角新增助手入口，一句话或语音即可解析为家务打卡、生活记录、菜篮子记价等结构化动作，全部经确认后才写入。',
                    '🎤 语音转文字：Android 系统语音识别（RECORD_AUDIO），Windows 自动降级为文字输入。',
                    '🧠 结构化匹配更细：菜篮子品类+品牌存在性判断、餐饮菜品与份量规格、家务成员与数量提取；AI 匹配值必须命中本地清单，不一致自动降级为新建确认。',
                    '🔑 设置中心新增 DeepSeek API Key 配置与隐私说明。',
                  ],
                ),
                const Divider(color: Colors.white12, height: 24),
                _buildVersionItem(
                  version: 'v1.4.16 (2026-08-18)',
                  isLatest: false,
                  changes: [
                    '🌐 更新检查与 APK 下载支持多源回退：直连 api.github.com 失败自动切换 ghproxy 等加速镜像，国内网络可用。',
                  ],
                ),
                const Divider(color: Colors.white12, height: 24),
                _buildVersionItem(
                  version: 'v1.4.15 (2026-08-17)',
                  isLatest: false,
                  changes: [
                    '📏 修复计步器误报「无计步器」与测量中窄屏溢出；自动更新修复 FileProvider 路径，拉起安装器失败改为系统引导授权。',
                  ],
                ),
                const Divider(color: Colors.white12, height: 24),
                _buildVersionItem(
                  version: 'v1.4.14 (2026-08-16)',
                  isLatest: false,
                  changes: [
                    '🏃 路线计步测量：开始记录步数、结束填倍数换算单程步数，多次测量取平均并支持手动登记；暂停/继续、排序偏好记忆等五项体验优化。',
                  ],
                ),
                const Divider(color: Colors.white12, height: 24),
                _buildVersionItem(
                  version: 'v1.4.13 (2026-08-15)',
                  isLatest: false,
                  changes: [
                    '🔧 自动更新修复：按设备架构自动选择安装包（arm64-v8a / armeabi-v7a / x86_64），不再固定下载 universal。',
                    '🚀 下载完成后自动拉起系统安装器，不再卡在 100%；取消下载/失败即时清理安装包，启动时兜底清理残留。',
                    '📱 餐饮菜单卡片排版优化：编辑/删除收纳进「⋯」菜单，名称与价格不再被图标挤成竖排。',
                    '🏷️ 文本框标签统一格式：品牌绿 + 加粗 + 阴影，与用户输入内容明显区分。',
                  ],
                ),
                const Divider(color: Colors.white12, height: 24),
                _buildVersionItem(
                  version: 'v1.4.12 (2026-08-14)',
                  isLatest: false,
                  changes: [
                    '🧺 菜篮子品牌管理：同一品类支持多品牌（如 佳农香蕉 / 辉众香蕉），打卡可填品牌（留空视为通用），详情页按品牌筛选，指标区、走势图、总表与浏览卡片同步展示品牌信息。',
                    '✍️ 模板文案专门化：菜篮子改用「商品图片 / 备忘」，影视改用「相关图片·剧照 / 长评」，美食保留「美食图片 / 特色说明·推荐好菜·备忘」，零食、书籍、景点、购物模板各配专属文案。',
                  ],
                ),
                const Divider(color: Colors.white12, height: 24),
                _buildVersionItem(
                  version: 'v1.4.11 (2026-08-13)',
                  isLatest: false,
                  changes: [
                    '🎬 WebDAV 同步补上 TMDB 海报缓存（cache/tmdb）：海报随图片一起增量备份/按缺失下载，恢复后自动重映射海报路径，影视剧集海报不再丢失。',
                  ],
                ),
                const Divider(color: Colors.white12, height: 24),
                _buildVersionItem(
                  version: 'v1.4.10 (2026-08-12)',
                  isLatest: false,
                  changes: [
                    '☁️ WebDAV 同步大修：修复 PROPFIND 大小写兼容（DUFS 等大写 D: 前缀服务器图片列表解析失败，导致恢复时图片拉不回来）。',
                    '🔍 新增「校验远端 / 数据概览 / 上传时间」：恢复前先确认备份库完整性、各表条数（路线/行走打卡/家务/生活记录/成员等）与上传时间。',
                    '🛡️ 备份升级为 VACUUM INTO 一致性快照并校验各表行数；恢复前先校验云端库，恢复后自动重映射图片路径到当前设备，并强制刷新路线/家务/生活/成员全部数据源。',
                  ],
                ),
                const Divider(color: Colors.white12, height: 24),
                _buildVersionItem(
                  version: 'v1.4.9 (2026-08-11)',
                  isLatest: false,
                  changes: [
                    '🔏 正式签名修复：v1.4.9 起所有 Release 使用同一把正式签名密钥，彻底解决跨版本「签名不一致需卸载重装」的问题。',
                    '⚠️ 一次性升级提示：本次从旧版升级需先卸载旧版（建议先在 数据与同步 → WebDAV 上传备份，重装后恢复，数据不丢）；v1.4.9 之后升级不再需要卸载。',
                  ],
                ),
                const Divider(color: Colors.white12, height: 24),
                _buildVersionItem(
                  version: 'v1.4.8 (2026-08-10)',
                  isLatest: false,
                  changes: [
                    '🧺 菜篮子板块：新增买菜/水果专用模板（果蔬分类 tag/单位/产地 + 单价/数量/购买渠道/新鲜度/备注），浏览卡片展示最近价、涨跌徽章与迷你走势图。',
                    '📈 菜篮子总表：筛选后一键进入总表页，全品类价格一览 + 多商品价格对比走势图（默认全展示，支持涨幅归一化对比）+ 分类月度均价柱状图 + 涨跌榜。',
                    '📊 单品价格走势：菜篮子详情页新增指标区（最近价/较上次/较7天/30天均价）与走势图（全部/近30天/近90天/今年范围切换，可叠加 7 日均线）。',
                    '⚙️ 设置整合：原「关于」Tab 合并进设置中心（品牌信息/更新记录/版本历史/架构说明），底部 Tab 精简为 路线/家务/生活/成员。',
                  ],
                ),
                const Divider(color: Colors.white12, height: 24),
                _buildVersionItem(
                  version: 'v1.4.7 (2026-08-09)',
                  isLatest: false,
                  changes: [
                    '🖱️ 卡片防误触：生活记录浏览卡片的编辑/删除按钮移入详情页，避免误操作。',
                    '🍽️ 餐饮位置/结算平台拆分：位置支持点击拉起地图（高德/百度/腾讯/系统地图），结算平台多选并在卡片与详情展示。',
                    '📍 位置一键定位：位置输入框旁新增定位按钮，GPS 定位 + 逆地理编码自动填写地址，也可手动填写。',
                    '🍛 菜品打分：菜单项新增 👍 推荐招牌菜 / 👎 不推荐 / 未点即一般，浏览卡片小字展示推荐与不推荐菜品。',
                    '⭐ 口味评价/环境服务改为 5 星滑杆：与推荐指数一致，更简单直观。',
                    '🗑️ 移除打卡弹窗中与点菜多选重复的「点了哪些菜」文本框。',
                  ],
                ),
                const Divider(color: Colors.white12, height: 24),
                _buildVersionItem(
                  version: 'v1.4.6 (2026-08-08)',
                  isLatest: false,
                  changes: [
                    '🧩 生活模板化：影视/餐饮/书籍/景点/购物/通用 6 大模板，分类自动绑定，表单各有针对性。',
                    '🛠️ 自定义字段：每个分类可追加文本/数字/单选/日期/图片/开关/标签等专属字段。',
                    '🎬 TMDB 影视导入：填 Key 后影视模板支持搜索自动填充片名、导演、海报等信息。',
                    '⚙️ 设置中心：右上角齿轮全局入口，收纳主题、视图、缓存、同步等全部选项。',
                    '🖼️ 缓存管理：选图复制入应用目录、上限自动清理、压缩质量可调。',
                    '☁️ WebDAV 同步：坚果云/Nextcloud 手动备份与恢复（数据库 + 图片增量）。',
                    '🔒 非破坏数据迁移：升级前自动备份旧库，全程事务增量迁移与行数对账，零数据丢失。',
                    '🍽️ 餐饮份量规格：菜品可自由添加 大份/小份、一两/二两 等规格并独立定价，打卡按规格计价自动合计。',
                    '📺 观看平台多选：影视平台改为多选，历史已用平台自动成为快捷选项，支持自定义新增（如 Jellyfin），卡片展示观看平台。',
                    '🎬 影视二级筛选：媒体类型 / 题材 / 上映年份 可叠加筛选；卡片展示题材徽章。',
                    '⏭️ 剧集进度：TMDB 读取总集数，打卡录入本次观看集数自动累计，卡片与详情展示 看了 x/y 集 进度条。',
                    '💬 短评长评：一句话点评快速展示在卡片，长评仅详情页展示；观看状态（想看/在追/看完/搁置/抛弃）快捷标记与筛选。',
                  ],
                ),
                const Divider(color: Colors.white12, height: 24),
                _buildVersionItem(
                  version: 'v1.3.0 (2026-07-30)',
                  isLatest: false,
                  changes: [
                    '👥 独立成员管理 Tab：新增专属成员档案 Bottom Tab，支持全员查看、编辑、删除与新增。',
                    '🎂 出生年月与动态年龄：成员档案引入出生日期登记，根据当前时间自动精准计算真实年龄。',
                    '⭐ 星级评分滑杆化：生活记录新增项目评分改为 1.0~5.0 粒度滑杆，防止弹窗溢出。',
                    '📝 家务打卡备注点标：针对写有打卡备注的格子添加琥珀色点标提示。',
                    '⚡ 界面精简与体验优化：优化底部 Tab 导航文本为精简双字，去除重复闪电图标与冗余标题注释。',
                  ],
                ),
                const Divider(color: Colors.white12, height: 24),
                _buildVersionItem(
                  version: 'v1.2.0 (2026-07-30)',
                  isLatest: false,
                  changes: [
                    '🛍️ 客观项目资产拆分：初次登记仅录入项目信息，移除初始消费设定。',
                    '🕒 分钟级打卡时刻：打卡时间精确定律至【yyyy-MM-dd HH:mm】，默认当前精确时刻，支持选历史分钟。',
                    '👥 成员同行复用：生活打卡可多选同行成员，共享统一家庭成员档案库并统计同行频率。',
                    '📊 独立项目详情页：卡片支持点击跳转独立详情界面，直观呈现高清画廊、累计消费与履约历史时间线。',
                  ],
                ),
                const Divider(color: Colors.white12, height: 24),
                _buildVersionItem(
                  version: 'v1.1.0 (2026-07-30)',
                  isLatest: false,
                  changes: [
                    '🏷️ 应用品牌重塑：全量重命名为【步履生活】。',
                    '🛍️ 生活记录大升级：支持探店、影视剧集、书籍阅读、景点场所等通用生活打卡与 1.0~5.0 星级评分。',
                    '👁️ Card ↔ 紧凑列表双视图：支持一键切换视图模式，上次展示偏好自动记忆与重启还原。',
                    '🗂️ 分类全量管理：侧边栏 Drawer 支持自定义分类重命名与安全平滑删除。',
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 关于：系统架构说明书（walkthrough.md）
  void _showWalkthroughDialog(BuildContext context) async {
    String content = '';
    try {
      content = await rootBundle.loadString('assets/walkthrough.md');
    } catch (_) {
      content = '暂未找到资源文档。';
    }
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.description, color: Color(0xFF10B981)),
            SizedBox(width: 8),
            Text('架构与说明文档 (walkthrough)'),
          ],
        ),
        content: SizedBox(
          width: 520,
          height: 420,
          child: SingleChildScrollView(
            child: Text(
              content,
              style: const TextStyle(fontSize: 13, height: 1.5, fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildVersionItem({
    required String version,
    required bool isLatest,
    required List<String> changes,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF6366F1),
              ),
            ),
            const SizedBox(width: 8),
            Text(version,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
            if (isLatest) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withAlpha(40),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('最新版',
                    style: TextStyle(fontSize: 10, color: Color(0xFF818CF8))),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: changes.map((c) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 6.0),
                child: Text(c,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.white70, height: 1.4)),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _section(String title, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF7DD3FC).withAlpha(55), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(45),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
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
      ),
    );
  }

  /// 按钮标签：窄屏下自动缩小字号保持单行，避免文字换行变形
  Widget _btnLabel(String text, {double fontSize = 14}) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(fontSize: fontSize),
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

  /// 默认筛选分类下拉：全部分类 + 当前生活分类（不存在的旧值回退为全部分类）
  Widget _buildDefaultCategoryDropdown(SettingsProvider settings) {
    final storeProvider = context.watch<StoreProvider>();
    final options = <String>['全部分类', ...storeProvider.categories.map((c) => c.name)];
    final value = options.contains(settings.storeDefaultFilterCategory)
        ? settings.storeDefaultFilterCategory
        : '全部分类';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: const Color(0xFF0F172A),
          iconEnabledColor: const Color(0xFF10B981),
          style: const TextStyle(fontSize: 13, color: Colors.white),
          items: options
              .map((name) => DropdownMenuItem(
                    value: name,
                    child: Text(name, style: const TextStyle(color: Colors.white)),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) settings.setStoreDefaultFilterCategory(v);
          },
        ),
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
                    const SizedBox(height: 16),
                    const Text('生活分类筛选栏', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 8),
                    _segmented<String>(
                      selected: {settings.storeFilterBarMode},
                      segments: const [
                        ButtonSegment(value: 'expanded', label: Text('展开显示'), icon: Icon(Icons.view_agenda_outlined, size: 16)),
                        ButtonSegment(value: 'collapsed', label: Text('悬浮按钮'), icon: Icon(Icons.filter_alt_outlined, size: 16)),
                      ],
                      onChanged: (v) => settings.setStoreFilterBarMode(v.first),
                    ),
                    if (settings.storeFilterBarMode == 'collapsed') ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Text('悬浮按钮透明度', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                          const Spacer(),
                          Text(
                            '${(settings.storeFilterFabOpacity * 100).round()}%',
                            style: const TextStyle(fontSize: 13, color: Color(0xFF10B981), fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Slider(
                        value: settings.storeFilterFabOpacity,
                        min: 0.2,
                        max: 1.0,
                        divisions: 8,
                        activeColor: const Color(0xFF10B981),
                        inactiveColor: Colors.white24,
                        label: '${(settings.storeFilterFabOpacity * 100).round()}%',
                        onChanged: (v) => settings.setStoreFilterFabOpacity(v),
                      ),
                    ],
                    const SizedBox(height: 16),
                    const Text('默认筛选分类', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 8),
                    _buildDefaultCategoryDropdown(settings),
                    const SizedBox(height: 8),
                    const Text('收起筛选栏后，通过右下角半透明悬浮按钮展开筛选；默认筛选分类下次启动生活记录时生效', style: TextStyle(fontSize: 11, color: Colors.white38)),
                    const SizedBox(height: 8),
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
                    const SizedBox(height: 8),
                    const Text('数据来源 TMDB（themoviedb.org）。可填 v3 API Key（32 位）或 v4 Read Access Token（eyJ 开头），两者都支持', style: TextStyle(fontSize: 11, color: Colors.white38)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _resetTemplateBindings,
                            icon: const Icon(Icons.restore, size: 18),
                            label: _btnLabel('恢复内置模板绑定'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('智能助手（DeepSeek）', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _deepseekKeyController,
                      obscureText: true,
                      decoration: InputDecoration(
                        hintText: '粘贴 DeepSeek API Key (sk-...)',
                        prefixIcon: const Icon(Icons.auto_awesome_outlined),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.save_outlined, size: 20),
                          onPressed: () {
                            settings.setDeepseekApiKey(_deepseekKeyController.text);
                            _toast('DeepSeek Key 已保存');
                          },
                        ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('说话或输入文字即可让 AI 帮你完成家务打卡、生活记录、菜篮子记价等；留空 = 禁用助手。语音仅本机转文字，成员/家务/生活清单文本会发送至 DeepSeek 处理，所有操作需你确认后才写入', style: TextStyle(fontSize: 11, color: Colors.white38)),
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
                            label: _btnLabel('立即上传'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _restoring ? null : _restoreNow,
                            icon: _restoring
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.download_outlined, size: 18),
                            label: _btnLabel('立即恢复'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _inspecting ? null : _verifyRemote,
                          icon: _inspecting
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.fact_check_outlined, size: 17),
                          label: _btnLabel('校验远端'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _inspecting ? null : _analyzeRemote,
                          icon: _inspecting
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.analytics_outlined, size: 17),
                          label: _btnLabel('数据概览'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _inspecting ? null : _remoteInfo,
                          icon: _inspecting
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.schedule_outlined, size: 17),
                          label: _btnLabel('上传时间'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      settings.webdavLastSync.isEmpty
                          ? '尚未同步过'
                          : '上次同步: ${settings.webdavLastSync}',
                      style: const TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                    const SizedBox(height: 8),
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
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final v in const [0, 50, 100, 200, 500])
                          ChoiceChip(
                            label: Text(v == 0 ? '不限' : '${v}MB'),
                            selected: settings.cacheLimitMB == v,
                            selectedColor: const Color(0xFF10B981).withAlpha(80),
                            backgroundColor: Colors.white.withAlpha(8),
                            side: BorderSide(
                              color: settings.cacheLimitMB == v
                                  ? const Color(0xFF10B981)
                                  : Colors.white24,
                            ),
                            onSelected: (_) => settings.setCacheLimitMB(v),
                          ),
                      ],
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
                            label: _btnLabel('按上限清理'),
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
                            label: _btnLabel('一键清空'),
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('旧图不受质量设置影响，仅影响新选图压缩', style: TextStyle(fontSize: 11, color: Colors.white38)),
                  ],
                )),

                // 账单导入（OCR 敏感词过滤）
                _section('账单导入（OCR 敏感词）', Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('OCR 账单送 AI 前，自动删除以下敏感词及其后的数字串；每行一个关键词。', style: TextStyle(fontSize: 11, color: Colors.white54)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _sensitiveKwCtrl,
                      maxLines: 6,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: '敏感词（每行一个）',
                        labelStyle: TextStyle(color: Colors.white54),
                        hintText: '交易单号\n商户单号\n订单号',
                        hintStyle: TextStyle(color: Colors.white24),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _resetSensitiveKeywords,
                            icon: const Icon(Icons.restart_alt, size: 18),
                            label: _btnLabel('恢复默认'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _saveSensitiveKeywords,
                            icon: const Icon(Icons.save_outlined, size: 18),
                            label: _btnLabel('保存'),
                            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                          ),
                        ),
                      ],
                    ),
                  ],
                )),

                // 应用更新
                _section('应用更新', Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.autorenew, color: Color(0xFF10B981)),
                      title: const Text('启动时自动检查更新', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                      subtitle: const Text('发现新版本时弹出提示，手动确认后下载安装', style: TextStyle(fontSize: 11, color: Colors.white54)),
                      value: settings.autoCheckUpdate,
                      onChanged: (v) => settings.setAutoCheckUpdate(v),
                    ),
                    const Divider(height: 8, color: Colors.white12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _checkingUpdate ? null : _checkUpdateNow,
                            icon: _checkingUpdate
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.system_update_alt, size: 18),
                            label: _btnLabel(_checkingUpdate ? '检查中…' : '检查更新'),
                            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('更新包来源为 GitHub Releases，安装完成后下次启动自动清理下载的 APK', style: TextStyle(fontSize: 11, color: Colors.white38)),
                  ],
                )),

                // 关于（合并原 About Tab：品牌信息 / 更新记录 / 架构说明）
                _section('关于', Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF10B981).withAlpha(70),
                                blurRadius: 14,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.asset('assets/icon/app_icon.png',
                                fit: BoxFit.cover),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('StepLife 步履生活',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white)),
                              const SizedBox(height: 4),
                              Text(
                                _appVersion.isEmpty
                                    ? '版本号: 获取中…'
                                    : '版本号: v$_appVersion',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF10B981),
                                    fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                '涵盖路线步量、家务习惯与生活记录 (探店/影视/图书) 的全能生活管理应用',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.white54),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Divider(color: Colors.white12, height: 1),
                    const SizedBox(height: 4),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.history_toggle_off,
                          color: Color(0xFF6366F1)),
                      title: const Text('更新记录与版本历史',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                      subtitle: const Text('查看各版本功能更新',
                          style: TextStyle(
                              fontSize: 11, color: Colors.white54)),
                      trailing:
                          const Icon(Icons.chevron_right, color: Colors.white38),
                      onTap: () => _showChangelogDialog(context),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.article_outlined,
                          color: Color(0xFF10B981)),
                      title: const Text('系统架构说明书',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                      subtitle: const Text('查看 walkthrough.md 架构与说明文档',
                          style: TextStyle(
                              fontSize: 11, color: Colors.white54)),
                      trailing:
                          const Icon(Icons.chevron_right, color: Colors.white38),
                      onTap: () => _showWalkthroughDialog(context),
                    ),
                    if (settings.backupWarning.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('提示: ${settings.backupWarning}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.orangeAccent)),
                    ],
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
