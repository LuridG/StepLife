import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../core/settings/settings_button.dart';
import '../../../core/update/app_updater.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

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
          width: 500,
          height: 400,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('关于本程序'),
        centerTitle: true,
        actions: [
          const SettingsButton(),
        ],
      ),
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
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withAlpha(80),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Image.asset('assets/icon/app_icon.png', fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'StepLife - 步履生活',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.5),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withAlpha(40),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF10B981).withAlpha(80)),
                  ),
                  child: FutureBuilder<PackageInfo>(
                    future: AppUpdater.packageInfo(),
                    builder: (context, snap) {
                      final info = snap.data;
                      final label = info == null
                          ? '版本号: 获取中…'
                          : '版本号: v${info.version} (Build ${info.buildNumber})';
                      return Text(
                        label,
                        style: const TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.bold),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '涵盖路线步量、家务习惯与生活记录 (探店/影视/图书) 的全能生活管理应用',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 24),

                _buildGlassCard(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.history_toggle_off, color: Color(0xFF6366F1)),
                            SizedBox(width: 8),
                            Text('更新记录与版本历史', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _buildVersionItem(
                          version: 'v1.4.7 (2026-08-09)',
                          isLatest: true,
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
                const SizedBox(height: 20),

                _buildGlassCard(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.article_outlined, color: Color(0xFF10B981)),
                            SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('系统架构说明书', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                Text('查看 walkthrough.md 资源', style: TextStyle(fontSize: 11, color: Colors.white54)),
                              ],
                            ),
                          ],
                        ),
                        OutlinedButton(
                          onPressed: () => _showWalkthroughDialog(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF10B981),
                            side: const BorderSide(color: Color(0xFF10B981)),
                          ),
                          child: const Text('查看文档'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
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
            Text(version, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            if (isLatest) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withAlpha(40),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('最新版', style: TextStyle(fontSize: 10, color: Color(0xFF818CF8))),
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
                child: Text(c, style: const TextStyle(fontSize: 12, color: Colors.white70, height: 1.4)),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildGlassCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(16),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withAlpha(35), width: 1.2),
          ),
          child: child,
        ),
      ),
    );
  }
}
