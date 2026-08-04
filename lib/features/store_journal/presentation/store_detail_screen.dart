import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../../../core/utils/map_launcher.dart';
import '../domain/store_models.dart';
import '../domain/life_templates.dart';
import '../providers/store_provider.dart';
import '../utils/basket_stats.dart';
import 'store_checkin_dialog.dart';

class StoreDetailScreen extends StatefulWidget {
  final StoreItem storeItem;

  const StoreDetailScreen({
    super.key,
    required this.storeItem,
  });

  @override
  State<StoreDetailScreen> createState() => _StoreDetailScreenState();
}

class _StoreDetailScreenState extends State<StoreDetailScreen> {
  /// 菜篮子品牌筛选（'全部' 或具体品牌）
  String _basketBrand = '全部';

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

  void _confirmDeleteStore(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('确认删除记录: ${widget.storeItem.name}?'),
        content: const Text('删除后该条打卡历史及照片关联将被安全移除。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              context.read<StoreProvider>().deleteStoreItem(widget.storeItem.id!);
              Navigator.of(ctx).pop();
              navigator.pop();
              messenger.showSnackBar(SnackBar(content: Text('已删除: ${widget.storeItem.name}')));
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('确认删除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final storeProvider = context.watch<StoreProvider>();
    final logs = storeProvider.getLogsForStore(widget.storeItem.id!);
    final totalCost = storeProvider.getTotalCostForStore(widget.storeItem.id!);

    // 模板专属字段（概览展示）
    StoreCategory? cat;
    for (final c in storeProvider.categories) {
      if (c.name == widget.storeItem.category) {
        cat = c;
        break;
      }
    }
    final tpl = LifeTemplates.byKey(cat?.templateKey ?? LifeTemplates.matchTemplateKey(widget.storeItem.category));
    final itemFields = [
      ...tpl.itemFields,
      ...(cat?.extraFields ?? const []).map((m) => TemplateField.fromJson(m)),
    ];
    final presentFields = itemFields
        .where((f) =>
            f.key != 'mediaType' &&
            f.key != 'genre' &&
            widget.storeItem.extras[f.key] != null &&
            widget.storeItem.extras[f.key].toString().isNotEmpty)
        .toList();
    // 通用模板在表单内自由添加的自定义字段：按 key 兜底渲染
    final knownKeys = itemFields.map((f) => f.key).toSet();
    final looseExtras = widget.storeItem.extras.entries
        .where((e) =>
            !knownKeys.contains(e.key) &&
            !(tpl.key == 'movie' &&
                (e.key == 'type' || e.key == 'totalEpisodes' || e.key == 'watchedEpisodes')) &&
            e.value != null &&
            e.value.toString().isNotEmpty)
        .map((e) => MapEntry(e.key, e.value.toString()))
        .toList();
    final menuItems = storeProvider.getMenuItemsForStore(widget.storeItem.id ?? 0);

    // 菜篮子：价格统计与走势
    final isBasket = tpl.key == 'basket';
    final basketBrands = isBasket ? BasketStats.brandsOf(logs) : const <String>[];
    final visibleBasketLogs = isBasket
        ? (_basketBrand == '全部'
            ? logs
            : logs.where((l) => BasketStats.brandLabel(l) == _basketBrand).toList())
        : const <StoreLog>[];
    final basketPoints = isBasket
        ? BasketStats.pricePoints(visibleBasketLogs)
        : const <({StoreLog log, double price})>[];
    final basketLatest = isBasket ? BasketStats.latestPrice(visibleBasketLogs) : null;
    final basketUnit = (widget.storeItem.extras['unit']?.toString() ?? '').isEmpty
        ? '斤'
        : widget.storeItem.extras['unit'].toString();
    final basketChangePrev = isBasket ? BasketStats.changeVsPrevious(visibleBasketLogs) : null;
    final basketChange7 = isBasket ? BasketStats.changeVsDaysAgo(visibleBasketLogs, 7) : null;
    final basketAvg30 = isBasket ? BasketStats.avgPriceSince(visibleBasketLogs, 30) : null;

    // 影视摘要：年份 · 导演/主演 · 片长（放在海报右侧信息区）
    final movieMetaParts = <String>[
      if ((widget.storeItem.extras['year']?.toString() ?? '').isNotEmpty)
        widget.storeItem.extras['year'].toString(),
      if ((widget.storeItem.extras['director']?.toString() ?? '').isNotEmpty)
        widget.storeItem.extras['director'].toString(),
      if (widget.storeItem.extras['duration'] is num)
        '${widget.storeItem.extras['duration']}分钟',
    ];

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
        title: Text(widget.storeItem.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: Colors.lightBlueAccent),
            tooltip: '编辑该项目',
            onPressed: () => Navigator.of(context).pop('edit'),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            tooltip: '删除该项目',
            onPressed: () => _confirmDeleteStore(context),
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
                // 高清照片画廊：非影视模板保留横滑大图（cover，无黑边）
                if (widget.storeItem.images.isNotEmpty && tpl.key != 'movie')
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: SizedBox(
                      height: 180,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: widget.storeItem.images.length,
                        itemBuilder: (ctx, idx) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 12.0),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.file(
                                File(widget.storeItem.images[idx]),
                                width: 260,
                                height: 180,
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, s) => Container(
                                  width: 260,
                                  height: 180,
                                  color: Colors.white10,
                                  child: const Icon(Icons.broken_image, color: Colors.white38),
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
                        if (tpl.key == 'movie') ...[
                          // 影视：海报左（2:3 竖版，完整展示无黑边）+ 文字右
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: widget.storeItem.images.isNotEmpty
                                    ? Image.file(
                                        File(widget.storeItem.images.first),
                                        width: 112,
                                        height: 168,
                                        fit: BoxFit.cover,
                                        errorBuilder: (c, e, s) => Container(
                                          width: 112,
                                          height: 168,
                                          color: Colors.white10,
                                          child: const Icon(Icons.movie_outlined, color: Colors.white38),
                                        ),
                                      )
                                    : Container(
                                        width: 112,
                                        height: 168,
                                        decoration: BoxDecoration(
                                          color: Colors.white10,
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        child: const Icon(Icons.movie_outlined, color: Colors.white38),
                                      ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF10B981).withAlpha(40),
                                            borderRadius: BorderRadius.circular(7),
                                          ),
                                          child: Text(widget.storeItem.category, style: const TextStyle(fontSize: 11, color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: Colors.indigo.withAlpha(60),
                                            borderRadius: BorderRadius.circular(7),
                                            border: Border.all(color: Colors.indigoAccent.withAlpha(110)),
                                          ),
                                          child: Text(
                                            resolveMediaType(widget.storeItem.extras) == '电影'
                                                ? '🎬 电影'
                                                : '📺 ${resolveMediaType(widget.storeItem.extras)}',
                                            style: const TextStyle(fontSize: 11, color: Colors.lightBlueAccent, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        if (resolveGenre(widget.storeItem.extras).isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: Colors.purple.withAlpha(50),
                                              borderRadius: BorderRadius.circular(7),
                                              border: Border.all(color: Colors.purpleAccent.withAlpha(90)),
                                            ),
                                            child: Text(
                                              '${resolveGenre(widget.storeItem.extras)} 题材',
                                              style: const TextStyle(fontSize: 11, color: Colors.purpleAccent, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      widget.storeItem.name,
                                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Row(
                                          children: List.generate(5, (sIdx) {
                                            return Icon(
                                              sIdx < widget.storeItem.rating.floor() ? Icons.star : Icons.star_border,
                                              color: Colors.amber,
                                              size: 18,
                                            );
                                          }),
                                        ),
                                        const SizedBox(width: 6),
                                        Text('${widget.storeItem.rating.toStringAsFixed(1)} 分', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14)),
                                      ],
                                    ),
                                    if (movieMetaParts.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        movieMetaParts.join(' · '),
                                        style: const TextStyle(fontSize: 12, color: Color(0xFF06B6D4), fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                    if (tpl.key == 'movie' &&
                                        resolveMediaType(widget.storeItem.extras) != '电影') ...[
                                      const SizedBox(height: 10),
                                      Text(
                                        '📺 观看进度 ${_watchedEpisodesOf(widget.storeItem)}/${_totalEpisodesOf(widget.storeItem) ?? '?'} 集',
                                        style: const TextStyle(fontSize: 12, color: Colors.lightBlueAccent, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 6),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: (_totalEpisodesOf(widget.storeItem) ?? 0) > 0
                                              ? (_watchedEpisodesOf(widget.storeItem) / _totalEpisodesOf(widget.storeItem)!).clamp(0.0, 1.0)
                                              : 0,
                                          minHeight: 6,
                                          backgroundColor: Colors.white12,
                                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF06B6D4)),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                          // 第 2/3 张图：小缩略图横滑
                          if (widget.storeItem.images.length > 1) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 88,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: widget.storeItem.images.length - 1,
                                itemBuilder: (ctx, i) {
                                  final path = widget.storeItem.images[i + 1];
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 8.0),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Image.file(
                                        File(path),
                                        width: 58,
                                        height: 88,
                                        fit: BoxFit.cover,
                                        errorBuilder: (c, e, s) => Container(
                                          width: 58,
                                          height: 88,
                                          color: Colors.white10,
                                          child: const Icon(Icons.image, color: Colors.white38, size: 18),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ] else ...[
                          // 非影视：分类 + 名称 + 评分
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withAlpha(40),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(widget.storeItem.category, style: const TextStyle(fontSize: 12, color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  widget.storeItem.name,
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
                                    sIdx < widget.storeItem.rating.floor() ? Icons.star : Icons.star_border,
                                    color: Colors.amber,
                                    size: 20,
                                  );
                                }),
                              ),
                              const SizedBox(width: 8),
                              Text('${widget.storeItem.rating.toStringAsFixed(1)} 分', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 15)),
                            ],
                          ),
                        ],
                        if (presentFields.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          ...presentFields.map((f) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(width: 92, child: Text(f.label, style: const TextStyle(fontSize: 12, color: Colors.white54))),
                                    Expanded(child: Text(_formatFieldValue(f, widget.storeItem.extras[f.key]), style: const TextStyle(fontSize: 12, color: Colors.white))),
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
                        if (isBasket) ...[
                          const SizedBox(height: 14),
                          const Divider(color: Colors.white12),
                          const SizedBox(height: 10),
                          if (basketBrands.length > 1) ...[
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final b in ['全部', ...basketBrands])
                                  ChoiceChip(
                                    label: Text(b,
                                        style: const TextStyle(fontSize: 11)),
                                    selected: _basketBrand == b,
                                    selectedColor: const Color(0xFF10B981).withAlpha(70),
                                    backgroundColor: Colors.white10,
                                    side: BorderSide(
                                        color: _basketBrand == b
                                            ? const Color(0xFF10B981)
                                            : Colors.white24),
                                    labelStyle: TextStyle(
                                        fontSize: 11,
                                        color: _basketBrand == b ? Colors.white : Colors.white70),
                                    onSelected: (_) =>
                                        setState(() => _basketBrand = b),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                          ],
                          Row(
                            children: [
                              _basketMetric(
                                  _basketBrand == '全部' ? '最近价' : '最近价 · $_basketBrand',
                                  basketLatest == null ? '—' : '¥${_fmtPrice(basketLatest)}/$basketUnit'),
                              _basketMetric('较上次', BasketStats.formatPct(basketChangePrev)),
                              _basketMetric('较7天', BasketStats.formatPct(basketChange7)),
                              _basketMetric('30天均价',
                                  basketAvg30 == null ? '—' : '¥${_fmtPrice(basketAvg30)}'),
                            ],
                          ),
                        ],
                        if (widget.storeItem.address != null && widget.storeItem.address!.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          if (tpl.key == 'dining') ...[
                            GestureDetector(
                              onTap: () => launchMapForPlace(context, widget.storeItem.address!),
                              child: Row(
                                children: [
                                  const Icon(Icons.place_outlined, color: Color(0xFF10B981), size: 16),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      '📍 位置: ${widget.storeItem.address}',
                                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                                    ),
                                  ),
                                  const Icon(Icons.open_in_new, color: Colors.white38, size: 13),
                                ],
                              ),
                            ),
                            if (_platformsOf(widget.storeItem).isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                '🛵 结算平台: ${_platformsOf(widget.storeItem).join(' · ')}',
                                style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ] else ...[
                            Text('📍 位置/平台: ${widget.storeItem.address}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                          ],
                        ],
                        if (widget.storeItem.notes != null && widget.storeItem.notes!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            '📝 ${tpl.notesFieldLabel}: ${widget.storeItem.notes}',
                            style: const TextStyle(color: Colors.white54, fontSize: 12, fontStyle: FontStyle.italic),
                          ),
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
                                        if (menuItems[i].rating == 1)
                                          const Padding(
                                            padding: EdgeInsets.only(right: 6),
                                            child: Icon(Icons.thumb_up, color: Color(0xFF10B981), size: 16),
                                          )
                                        else if (menuItems[i].rating == -1)
                                          const Padding(
                                            padding: EdgeInsets.only(right: 6),
                                            child: Icon(Icons.thumb_down, color: Colors.redAccent, size: 16),
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

                // 菜篮子：价格走势图（范围切换 + 7 日均线叠加）
                if (isBasket) ...[
                  const SizedBox(height: 20),
                  _BasketPriceChart(points: basketPoints, unit: basketUnit, brand: _basketBrand),
                ],
                const SizedBox(height: 20),

                // 分钟级打卡履约历史时间线 (Timeline)
                const Row(
                  children: [
                    Icon(Icons.history, color: Color(0xFF10B981), size: 20),
                    SizedBox(width: 8),
                    Text('打卡历史', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
                const SizedBox(height: 12),

                logs.isEmpty
                    ? _buildGlassCard(
                        child: const Padding(
                          padding: EdgeInsets.all(24.0),
                          child: Center(
                            child: Text('暂无打卡记录，点击主页【⚡ 记一次打卡】添加。', style: TextStyle(color: Colors.white54, fontSize: 13)),
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
                                            if (isBasket && log.extras['price'] is num)
                                              Container(
                                                margin: const EdgeInsets.only(right: 6),
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF10B981).withAlpha(30),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  '单价 ¥${(log.extras['price'] as num).toString()}/$basketUnit',
                                                  style: const TextStyle(
                                                      fontSize: 11,
                                                      color: Color(0xFF10B981),
                                                      fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                            if ((log.extras['brand']?.toString() ?? '').trim().isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(left: 6),
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFF59E0B).withAlpha(35),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    '🏷️ ${log.extras['brand']}',
                                                    style: const TextStyle(
                                                        fontSize: 11,
                                                        color: Color(0xFFF59E0B),
                                                        fontWeight: FontWeight.w600),
                                                  ),
                                                ),
                                              ),
                                            IconButton(
                                              icon: const Icon(Icons.edit_outlined, color: Colors.lightBlueAccent, size: 18),
                                              tooltip: '修改打卡',
                                              onPressed: () {
                                                showDialog(
                                                  context: context,
                                                  builder: (ctx) => StoreCheckinDialog(
                                                    store: widget.storeItem,
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

  int _watchedEpisodesOf(StoreItem store) {
    final v = store.extras['watchedEpisodes'];
    return (v is num) ? v.toInt() : 0;
  }

  int? _totalEpisodesOf(StoreItem store) {
    final v = store.extras['totalEpisodes'];
    return (v is num) ? v.toInt() : null;
  }

  /// 结算平台/观看平台：兼容多选 List 与旧版单值 String
  List<String> _platformsOf(StoreItem store) {
    final v = store.extras['platform'];
    if (v == null) return const [];
    final list = v is List
        ? v.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
        : [v.toString()];
    return list;
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
      case TemplateFieldType.multiChoice:
        return (value is List) ? value.join(' / ') : value.toString();
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

  Widget _basketMetric(String label, String value) {
    final up = value.startsWith('+');
    final down = value.startsWith('-');
    final color = down
        ? const Color(0xFF10B981)
        : (up ? Colors.redAccent : Colors.white);
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 4),
          Text(value,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: color)),
        ],
      ),
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

/// 菜篮子价格走势图：范围切换（全部/近30天/近90天/今年）+ 7 日均线叠加
class _BasketPriceChart extends StatefulWidget {
  final List<({StoreLog log, double price})> points;
  final String unit;
  final String brand;

  const _BasketPriceChart({
    required this.points,
    required this.unit,
    this.brand = '全部',
  });

  @override
  State<_BasketPriceChart> createState() => _BasketPriceChartState();
}

class _BasketPriceChartState extends State<_BasketPriceChart> {
  static const _ranges = ['全部', '近30天', '近90天', '今年'];
  String _range = '全部';
  bool _showMa = false;

  List<({StoreLog log, double price})> get _filtered {
    final now = DateTime.now();
    final pts = widget.points;
    switch (_range) {
      case '近30天':
        return pts
            .where((p) =>
                !p.log.timestamp.isBefore(now.subtract(const Duration(days: 30))))
            .toList();
      case '近90天':
        return pts
            .where((p) =>
                !p.log.timestamp.isBefore(now.subtract(const Duration(days: 90))))
            .toList();
      case '今年':
        return pts.where((p) => p.log.timestamp.year == now.year).toList();
      default:
        return pts;
    }
  }

  String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final pts = _filtered;
    if (pts.isEmpty) {
      return _buildCard(
        child: const Padding(
          padding: EdgeInsets.all(20.0),
          child: Center(
            child: Text('该时间范围内暂无价格记录',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
          ),
        ),
      );
    }

    final n = pts.length;
    final prices = pts.map((p) => p.price).toList();
    var minP = prices.reduce((a, b) => a < b ? a : b);
    var maxP = prices.reduce((a, b) => a > b ? a : b);
    if (maxP == minP) {
      maxP += 1;
      minP -= 1;
    }
    final yPad = (maxP - minP) * 0.15;
    minP -= yPad;
    maxP += yPad;
    final yInterval = (maxP - minP) / 4;
    final xMax = n > 1 ? (n - 1).toDouble() : 1.0;

    // 7 日均线
    final ma = <double>[];
    for (var i = 0; i < n; i++) {
      final winStart = pts[i].log.timestamp.subtract(const Duration(days: 7));
      double sum = 0;
      var cnt = 0;
      for (var j = 0; j <= i; j++) {
        if (!pts[j].log.timestamp.isBefore(winStart)) {
          sum += pts[j].price;
          cnt++;
        }
      }
      ma.add(cnt > 0 ? sum / cnt : pts[i].price);
    }

    return _buildCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('📈 价格走势',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const Spacer(),
                const Text('7日均线',
                    style: TextStyle(fontSize: 11, color: Colors.white54)),
                Switch(
                  value: _showMa,
                  activeThumbColor: Colors.amber,
                  onChanged: (v) => setState(() => _showMa = v),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final r in _ranges)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(r, style: const TextStyle(fontSize: 11)),
                        selected: _range == r,
                        selectedColor:
                            const Color(0xFF10B981).withAlpha(90),
                        onSelected: (_) => setState(() => _range = r),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 190,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: xMax,
                  minY: minP,
                  maxY: maxP,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (v) =>
                        const FlLine(color: Colors.white12, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 44,
                        interval: yInterval,
                        getTitlesWidget: (value, meta) => Text(
                          _fmt(value),
                          style: const TextStyle(
                              fontSize: 9, color: Colors.white38),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 26,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final i = value.round();
                          if (i != 0 &&
                              i != n - 1 &&
                              !(n > 4 && i == n ~/ 2)) {
                            return const SizedBox.shrink();
                          }
                          final idx = i < 0 ? 0 : (i > n - 1 ? n - 1 : i);
                          final t = pts[idx].log.timestamp;
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '${t.month}/${t.day}',
                              style: const TextStyle(
                                  fontSize: 9, color: Colors.white38),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) => const Color(0xFF1E293B),
                      getTooltipItems: (spots) => spots.map((s) {
                        final raw = s.x.round();
                        final i = raw < 0 ? 0 : (raw > n - 1 ? n - 1 : raw);
                        final t = pts[i].log.timestamp;
                        final isMa = s.bar.color == Colors.amber;
                        return LineTooltipItem(
                          '${isMa ? '7日均线' : DateFormat('yyyy-MM-dd').format(t)}: '
                          '${s.y.toStringAsFixed(2)}',
                          const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                        );
                      }).toList(),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (var i = 0; i < n; i++)
                          FlSpot(i.toDouble(), prices[i]),
                      ],
                      color: const Color(0xFF10B981),
                      barWidth: 3,
                      isCurved: n > 2,
                      dotData: FlDotData(
                        show: n <= 20,
                        getDotPainter: (spot, percent, bar, index) =>
                            FlDotCirclePainter(
                          radius: 3,
                          color: const Color(0xFF10B981),
                          strokeWidth: 0,
                          strokeColor: const Color(0xFF10B981),
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: const Color(0xFF10B981).withAlpha(35),
                      ),
                    ),
                    if (_showMa && ma.length >= 3)
                      LineChartBarData(
                        spots: [
                          for (var i = 0; i < n; i++)
                            FlSpot(i.toDouble(), ma[i]),
                        ],
                        color: Colors.amber,
                        barWidth: 2,
                        isCurved: true,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(show: false),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '最近价 ¥${_fmt(prices.last)}/${widget.unit} · 共 $n 条价格记录${widget.brand == '全部' ? '' : ' · 品牌: ${widget.brand}'}',
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
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
