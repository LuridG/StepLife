import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../domain/store_models.dart';
import '../domain/life_templates.dart';
import '../providers/store_provider.dart';
import 'store_checkin_dialog.dart';

class StoreDetailScreen extends StatelessWidget {
  final StoreItem storeItem;

  const StoreDetailScreen({
    super.key,
    required this.storeItem,
  });

  void _confirmDeleteLog(BuildContext context, StoreLog log) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除此次打卡记录?'),
        content: Text('打卡时间: ${DateFormat('yyyy-MM-dd HH:mm').format(log.timestamp)}\n消费: ¥${log.cost?.toStringAsFixed(1) ?? "0"}'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              context.read<StoreProvider>().deleteStoreLog(log.id!);
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已删除该条打卡记录')));
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('删除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final storeProvider = context.watch<StoreProvider>();
    final logs = storeProvider.getLogsForStore(storeItem.id!);
    final totalCost = storeProvider.getTotalCostForStore(storeItem.id!);

    // 模板专属字段（概览展示）
    StoreCategory? cat;
    for (final c in storeProvider.categories) {
      if (c.name == storeItem.category) {
        cat = c;
        break;
      }
    }
    final tpl = LifeTemplates.byKey(cat?.templateKey ?? LifeTemplates.matchTemplateKey(storeItem.category));
    final itemFields = [
      ...tpl.itemFields,
      ...(cat?.extraFields ?? const []).map((m) => TemplateField.fromJson(m)),
    ];
    final presentFields = itemFields
        .where((f) =>
            f.key != 'mediaType' &&
            f.key != 'genre' &&
            storeItem.extras[f.key] != null &&
            storeItem.extras[f.key].toString().isNotEmpty)
        .toList();
    // 通用模板在表单内自由添加的自定义字段：按 key 兜底渲染
    final knownKeys = itemFields.map((f) => f.key).toSet();
    final looseExtras = storeItem.extras.entries
        .where((e) =>
            !knownKeys.contains(e.key) &&
            !(tpl.key == 'movie' && e.key == 'type') &&
            e.value != null &&
            e.value.toString().isNotEmpty)
        .map((e) => MapEntry(e.key, e.value.toString()))
        .toList();
    final menuItems = storeProvider.getMenuItemsForStore(storeItem.id ?? 0);

    final logFieldLabels = {
      for (final f in [...tpl.checkinFields, ...(cat?.extraFields ?? const []).map((m) => TemplateField.fromJson(m))])
        f.key: f.label,
    };

    // 计算同行成员频率
    final Map<String, int> visitorCounts = {};
    for (final log in logs) {
      for (final vName in log.visitorNames) {
        visitorCounts[vName] = (visitorCounts[vName] ?? 0) + 1;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(storeItem.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.star, color: Colors.amber),
            tooltip: '评分 ${storeItem.rating}',
            onPressed: () {},
          ),
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
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 高清照片画廊
                if (storeItem.images.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: SizedBox(
                      height: 180,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: storeItem.images.length,
                        itemBuilder: (ctx, idx) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 12.0),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                color: Colors.black38,
                                child: Image.file(
                                  File(storeItem.images[idx]),
                                  width: 260,
                                  height: 180,
                                  fit: tpl.key == 'movie' ? BoxFit.contain : BoxFit.cover,
                                  errorBuilder: (c, e, s) => Container(
                                    width: 260,
                                    height: 180,
                                    color: Colors.white10,
                                    child: const Icon(Icons.broken_image, color: Colors.white38),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                // 总体概览卡片
                _buildGlassCard(
                  child: Padding(
                    padding: const EdgeInsets.all(18.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withAlpha(40),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(storeItem.category, style: const TextStyle(fontSize: 12, color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                            ),
                            if (tpl.key == 'movie') ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.indigo.withAlpha(60),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.indigoAccent.withAlpha(110)),
                                ),
                                child: Text(
                                  resolveMediaType(storeItem.extras) == '电影'
                                      ? '🎬 电影'
                                      : '📺 ${resolveMediaType(storeItem.extras)}',
                                  style: const TextStyle(fontSize: 12, color: Colors.lightBlueAccent, fontWeight: FontWeight.bold),
                                ),
                              ),
                              if (resolveGenre(storeItem.extras).isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.purple.withAlpha(50),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.purpleAccent.withAlpha(90)),
                                  ),
                                  child: Text(
                                    '${resolveGenre(storeItem.extras)} 题材',
                                    style: const TextStyle(fontSize: 12, color: Colors.purpleAccent, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ],
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                storeItem.name,
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Row(
                              children: List.generate(5, (sIdx) {
                                return Icon(
                                  sIdx < storeItem.rating.floor() ? Icons.star : Icons.star_border,
                                  color: Colors.amber,
                                  size: 20,
                                );
                              }),
                            ),
                            const SizedBox(width: 8),
                            Text('${storeItem.rating.toStringAsFixed(1)} 分', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 15)),
                          ],
                        ),
                        if (presentFields.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          ...presentFields.map((f) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(width: 92, child: Text(f.label, style: const TextStyle(fontSize: 12, color: Colors.white54))),
                                    Expanded(child: Text(_formatFieldValue(f, storeItem.extras[f.key]), style: const TextStyle(fontSize: 12, color: Colors.white))),
                                  ],
                                ),
                              )),
                        ],
                        if (looseExtras.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          ...looseExtras.map((en) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(width: 92, child: Text(en.key, style: const TextStyle(fontSize: 12, color: Colors.white54))),
                                    Expanded(child: Text(en.value, style: const TextStyle(fontSize: 12, color: Colors.white))),
                                  ],
                                ),
                              )),
                        ],
                        const SizedBox(height: 14),
                        const Divider(color: Colors.white12),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  const Text('累计打卡', style: TextStyle(color: Colors.white54, fontSize: 12)),
                                  const SizedBox(height: 4),
                                  Text('${logs.length} 次', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                                ],
                              ),
                            ),
                            Container(width: 1, height: 35, color: Colors.white12),
                            Expanded(
                              child: Column(
                                children: [
                                  const Text('累计总消费', style: TextStyle(color: Colors.white54, fontSize: 12)),
                                  const SizedBox(height: 4),
                                  Text('¥${totalCost.toStringAsFixed(1)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (storeItem.address != null && storeItem.address!.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Text('📍 位置/平台: ${storeItem.address}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        ],
                        if (storeItem.notes != null && storeItem.notes!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text('📝 特色备忘: ${storeItem.notes}', style: const TextStyle(color: Colors.white54, fontSize: 12, fontStyle: FontStyle.italic)),
                        ],
                        if (visitorCounts.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          const Text('👥 成员同行统计:', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            children: visitorCounts.entries.map((e) {
                              return Chip(
                                backgroundColor: const Color(0xFF6366F1).withAlpha(30),
                                side: BorderSide(color: const Color(0xFF6366F1).withAlpha(80)),
                                label: Text('${e.key}: ${e.value} 次', style: const TextStyle(fontSize: 11, color: Colors.white)),
                              );
                            }).toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // 餐饮菜单：固定菜品与价格（打卡点菜自动合计）
                if (tpl.key == 'dining') ...[
                  const SizedBox(height: 20),
                  const Row(
                    children: [
                      Icon(Icons.restaurant_menu, color: Color(0xFF10B981), size: 20),
                      SizedBox(width: 8),
                      Text('店铺菜单', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  menuItems.isEmpty
                      ? _buildGlassCard(
                          child: const Padding(
                            padding: EdgeInsets.all(20.0),
                            child: Center(
                              child: Text('暂无菜单，编辑店铺时可添加固定菜品与价格，之后打卡点菜自动统计消费。', style: TextStyle(color: Colors.white54, fontSize: 13)),
                            ),
                          ),
                        )
                      : _buildGlassCard(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            child: Column(
                              children: [
                                for (int i = 0; i < menuItems.length; i++) ...[
                                  if (i > 0) const Divider(color: Colors.white12, height: 1),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    child: Row(
                                      children: [
                                        if (menuItems[i].imagePath != null && menuItems[i].imagePath!.isNotEmpty)
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(10),
                                            child: Image.file(
                                              File(menuItems[i].imagePath!),
                                              width: 46,
                                              height: 46,
                                              fit: BoxFit.cover,
                                              errorBuilder: (c, e, s) => Container(
                                                width: 46,
                                                height: 46,
                                                color: Colors.white10,
                                                child: const Icon(Icons.restaurant, color: Colors.white38, size: 22),
                                              ),
                                            ),
                                          )
                                        else
                                          Container(
                                            width: 46,
                                            height: 46,
                                            decoration: BoxDecoration(
                                              color: Colors.white10,
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: const Icon(Icons.restaurant_menu, color: Colors.white38, size: 22),
                                          ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            menuItems[i].name,
                                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                                          ),
                                        ),
                                        Text(
                                          '¥${_fmtPrice(menuItems[i].price)}',
                                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                ],

                // 分钟级打卡履约历史时间线 (Timeline)
                const Row(
                  children: [
                    Icon(Icons.history, color: Color(0xFF10B981), size: 20),
                    SizedBox(width: 8),
                    Text('打卡履约历史时间线', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
                const SizedBox(height: 12),

                logs.isEmpty
                    ? _buildGlassCard(
                        child: const Padding(
                          padding: EdgeInsets.all(24.0),
                          child: Center(
                            child: Text('暂无打卡履约历史记录，点击主页【⚡ 记一次打卡】添加。', style: TextStyle(color: Colors.white54, fontSize: 13)),
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: logs.length,
                        itemBuilder: (ctx, idx) {
                          final log = logs[idx];
                          final timeStr = DateFormat('yyyy-MM-dd HH:mm').format(log.timestamp);

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: _buildGlassCard(
                              child: Padding(
                                padding: const EdgeInsets.all(14.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(Icons.access_time_filled, color: Color(0xFF10B981), size: 16),
                                            const SizedBox(width: 6),
                                            Text(timeStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                                          ],
                                        ),
                                        Row(
                                          children: [
                                            if (log.cost != null && log.cost! > 0)
                                              Text('¥${log.cost!.toStringAsFixed(1)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF10B981), fontSize: 14)),
                                            IconButton(
                                              icon: const Icon(Icons.edit_outlined, color: Colors.lightBlueAccent, size: 18),
                                              tooltip: '修改打卡',
                                              onPressed: () {
                                                showDialog(
                                                  context: context,
                                                  builder: (ctx) => StoreCheckinDialog(
                                                    store: storeItem,
                                                    existingLog: log,
                                                  ),
                                                );
                                              },
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                                              onPressed: () => _confirmDeleteLog(context, log),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    if (log.extras.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      ..._formatLogExtras(log, logFieldLabels),
                                    ],
                                    if (log.menuNames.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('点菜: ', style: TextStyle(fontSize: 12, color: Colors.white54)),
                                          Expanded(
                                            child: Wrap(
                                              spacing: 6,
                                              runSpacing: 4,
                                              children: log.menuNames.map((n) {
                                                return Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF10B981).withAlpha(25),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(color: const Color(0xFF10B981).withAlpha(60)),
                                                  ),
                                                  child: Text(n, style: const TextStyle(fontSize: 11, color: Color(0xFF10B981))),
                                                );
                                              }).toList(),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    if (log.visitorNames.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          const Text('同行人员: ', style: TextStyle(fontSize: 12, color: Colors.white54)),
                                          Wrap(
                                            spacing: 6,
                                            children: log.visitorNames.map((v) {
                                              return Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.white.withAlpha(15),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(v, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                                              );
                                            }).toList(),
                                          ),
                                        ],
                                      ),
                                    ],
                                    if (log.memo != null && log.memo!.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Text('💬 心得: ${log.memo}', style: const TextStyle(fontSize: 12, color: Colors.white70, fontStyle: FontStyle.italic)),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 金额格式化：整数不带小数，非整数保留 1 位小数
  String _fmtPrice(double v) {
    if (v == v.roundToDouble()) {
      return v.toStringAsFixed(0);
    }
    return v.toStringAsFixed(1);
  }

  String _formatFieldValue(TemplateField f, dynamic value) {
    if (value == null) return '';
    switch (f.type) {
      case TemplateFieldType.switchField:
        return value == true ? '是' : '否';
      case TemplateFieldType.images:
        return (value is List) ? '${value.length} 张图片' : value.toString();
      case TemplateFieldType.image:
        return '已添加图片';
      case TemplateFieldType.rating:
        return '⭐ ${value is num ? value.toStringAsFixed(1) : value.toString()}';
      default:
        return value.toString();
    }
  }

  /// 打卡记录中的模板字段摘要
  List<Widget> _formatLogExtras(StoreLog log, Map<String, String> labels) {
    final widgets = <Widget>[];
    log.extras.forEach((key, value) {
      if (value == null) return;
      final str = value.toString();
      if (str.isEmpty || str == 'false') return;
      final display = value == true ? '是' : str;
      final label = labels[key] ?? key;
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$label: ', style: const TextStyle(fontSize: 12, color: Colors.white54)),
            Expanded(
              child: Text(display, style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ),
          ],
        ),
      ));
    });
    return widgets;
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
