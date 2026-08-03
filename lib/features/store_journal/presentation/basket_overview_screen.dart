import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../domain/store_models.dart';
import '../domain/life_templates.dart';
import '../providers/store_provider.dart';
import '../utils/basket_stats.dart';
import 'store_detail_screen.dart';

/// 菜篮子「总表」：全品类价格总览、价格对比走势图、分类月度均价、涨跌榜。
/// 对比图默认展示当前筛选范围内的全部商品（默认全部分类/全部月份/全部涨跌）。
class BasketOverviewScreen extends StatefulWidget {
  const BasketOverviewScreen({super.key});

  @override
  State<BasketOverviewScreen> createState() => _BasketOverviewScreenState();
}

class _BasketOverviewScreenState extends State<BasketOverviewScreen> {
  static const _palette = <Color>[
    Color(0xFF10B981), Color(0xFF6366F1), Color(0xFFF59E0B), Color(0xFFEC4899),
    Color(0xFF06B6D4), Color(0xFF8B5CF6), Color(0xFFEF4444), Color(0xFF84CC16),
    Color(0xFF14B8A6), Color(0xFFF97316), Color(0xFF3B82F6), Color(0xFFA855F7),
  ];

  String _selectedTag = '全部';
  String _selectedMonth = '全部月份';
  String _selectedTrend = '全部涨跌';
  String _sortBy = '最近更新';
  bool _normalize = false;

  static String _monthKey(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}';

  static String _templateKeyOf(StoreProvider provider, StoreItem item) {
    for (final c in provider.categories) {
      if (c.name == item.category) return c.templateKey;
    }
    return LifeTemplates.matchTemplateKey(item.category);
  }

  String _fmtPrice(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }

  String _unitOf(StoreItem item) =>
      (item.extras['unit']?.toString() ?? '').isEmpty
          ? '斤'
          : item.extras['unit'].toString();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StoreProvider>();
    final allBasket = provider.storeItems
        .where((i) => _templateKeyOf(provider, i) == 'basket')
        .toList();

    // 分类 / 月份选项（按现有数据动态生成）
    final tags = <String>{};
    final months = <String>{};
    for (final item in allBasket) {
      final t = item.extras['basketTag']?.toString() ?? '';
      if (t.isNotEmpty) tags.add(t);
      for (final log in provider.getLogsForStore(item.id ?? 0)) {
        final p = (log.extras['price'] as num?)?.toDouble() ?? 0;
        if (p > 0) months.add(_monthKey(log.timestamp));
      }
    }
    final sortedTags = tags.toList()..sort();
    final sortedMonths = months.toList()..sort();

    var candidates = allBasket;
    if (_selectedTag != '全部') {
      candidates = candidates
          .where((i) =>
              (i.extras['basketTag']?.toString() ?? '') == _selectedTag)
          .toList();
    }

    // 行数据：价格点 + 涨跌指标
    final rows = <_BasketRow>[];
    for (final item in candidates) {
      final logs = provider.getLogsForStore(item.id ?? 0);
      var pts = BasketStats.pricePoints(logs);
      if (pts.isEmpty) continue;
      if (_selectedMonth != '全部月份') {
        pts = pts
            .where((p) => _monthKey(p.log.timestamp) == _selectedMonth)
            .toList();
        if (pts.isEmpty) continue;
      }
      final trend = BasketStats.trendDirection(logs);
      if (_selectedTrend != '全部涨跌' && trend != _selectedTrend) continue;
      final last = pts.last;
      final channelRaw = last.log.extras['channel'];
      final channel = channelRaw is List
          ? channelRaw.join(' / ')
          : (channelRaw?.toString() ?? '');
      rows.add(_BasketRow(
        item: item,
        points: pts,
        latestPrice: last.price,
        latestTime: last.log.timestamp,
        changePrev: BasketStats.changeVsPrevious(logs),
        changeMonth: BasketStats.changeVsLastMonth(logs),
        checkinCount: logs.length,
        lastChannel: channel,
      ));
    }

    // 排序
    switch (_sortBy) {
      case '涨幅最大':
        rows.sort((a, b) =>
            (b.changePrev ?? -999).compareTo(a.changePrev ?? -999));
        break;
      case '降幅最大':
        rows.sort(
            (a, b) => (a.changePrev ?? 999).compareTo(b.changePrev ?? 999));
        break;
      case '价格最高':
        rows.sort((a, b) => b.latestPrice.compareTo(a.latestPrice));
        break;
      case '价格最低':
        rows.sort((a, b) => a.latestPrice.compareTo(b.latestPrice));
        break;
      default:
        rows.sort((a, b) => b.latestTime.compareTo(a.latestTime));
    }

    // 统计摘要
    final totalLogs = rows.fold<int>(0, (s, r) => s + r.points.length);
    final nowKey = _monthKey(DateTime.now());
    final monthCount = rows.fold<int>(
        0,
        (s, r) =>
            s +
            r.points
                .where((p) => _monthKey(p.log.timestamp) == nowKey)
                .length);
    final latestAvg = rows.isEmpty
        ? null
        : rows.map((r) => r.latestPrice).reduce((a, b) => a + b) /
            rows.length;
    _BasketRow? biggestRise;
    _BasketRow? biggestFall;
    for (final r in rows) {
      if (r.changePrev == null) continue;
      if (biggestRise == null || r.changePrev! > biggestRise.changePrev!) {
        biggestRise = r;
      }
      if (biggestFall == null || r.changePrev! < biggestFall.changePrev!) {
        biggestFall = r;
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('菜篮子 · 总表')),
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
                _buildSummaryCard(
                  totalLogs: totalLogs,
                  monthCount: monthCount,
                  latestAvg: latestAvg,
                  biggestRise: biggestRise,
                  biggestFall: biggestFall,
                ),
                const SizedBox(height: 14),
                _buildFilterCard(
                  sortedTags: sortedTags,
                  sortedMonths: sortedMonths,
                ),
                const SizedBox(height: 18),
                _sectionTitle(Icons.table_chart_outlined, '全品类一览（点击查看详情）'),
                const SizedBox(height: 10),
                rows.isEmpty
                    ? _buildEmptyCard('当前筛选范围内暂无价格记录')
                    : _buildOverviewTable(rows),
                if (rows.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  _sectionTitle(Icons.query_stats, '价格对比走势图'),
                  const SizedBox(height: 6),
                  _buildComparisonChart(rows),
                  const SizedBox(height: 22),
                  _sectionTitle(Icons.bar_chart, '分类月度均价'),
                  const SizedBox(height: 6),
                  _buildMonthlyBarChart(rows),
                  const SizedBox(height: 22),
                  _sectionTitle(Icons.trending_up, '涨跌榜（较上次打卡）'),
                  const SizedBox(height: 6),
                  _buildRankingList(rows),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF10B981), size: 20),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
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

  Widget _buildEmptyCard(String text) {
    return _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: Text(text,
              style: const TextStyle(color: Colors.white54, fontSize: 13)),
        ),
      ),
    );
  }

  Widget _buildSummaryCard({
    required int totalLogs,
    required int monthCount,
    required double? latestAvg,
    required _BasketRow? biggestRise,
    required _BasketRow? biggestFall,
  }) {
    Widget stat(String label, String value, {Color? color}) {
      return Expanded(
        child: Column(
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white54, fontSize: 11)),
            const SizedBox(height: 4),
            Text(value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: color ?? Colors.white)),
          ],
        ),
      );
    }

    return _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Row(
          children: [
            stat('记录总数', '$totalLogs 条'),
            stat('本月记录', '$monthCount 条'),
            stat('最新均价', latestAvg == null ? '—' : '¥${_fmtPrice(latestAvg)}'),
            stat('涨幅最大',
                biggestRise == null
                    ? '—'
                    : '${biggestRise.item.name}\n${BasketStats.formatPct(biggestRise.changePrev)}',
                color: const Color(0xFF10B981)),
            stat('降幅最大',
                biggestFall == null
                    ? '—'
                    : '${biggestFall.item.name}\n${BasketStats.formatPct(biggestFall.changePrev)}',
                color: Colors.redAccent),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterCard({
    required List<String> sortedTags,
    required List<String> sortedMonths,
  }) {
    Widget chipRow(List<Widget> children) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: children),
      );
    }

    Widget chip(String label,
        {required bool selected, required VoidCallback onTap, Color? color}) {
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: FilterChip(
          label: Text(label, style: const TextStyle(fontSize: 12)),
          selected: selected,
          selectedColor: (color ?? const Color(0xFF10B981)).withAlpha(90),
          onSelected: (_) => onTap(),
        ),
      );
    }

    return _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            chipRow([
              chip('全部', selected: _selectedTag == '全部',
                  onTap: () => setState(() => _selectedTag = '全部')),
              ...sortedTags.map((t) => chip(t,
                  selected: _selectedTag == t,
                  onTap: () => setState(() => _selectedTag = t))),
            ]),
            const SizedBox(height: 8),
            chipRow([
              chip('全部月份', selected: _selectedMonth == '全部月份',
                  onTap: () => setState(() => _selectedMonth = '全部月份')),
              ...sortedMonths.map((m) => chip(m,
                  selected: _selectedMonth == m,
                  color: const Color(0xFF6366F1),
                  onTap: () => setState(() => _selectedMonth = m))),
            ]),
            const SizedBox(height: 8),
            chipRow([
              chip('全部涨跌', selected: _selectedTrend == '全部涨跌',
                  onTap: () => setState(() => _selectedTrend = '全部涨跌')),
              chip('上涨', selected: _selectedTrend == 'up',
                  color: const Color(0xFF10B981),
                  onTap: () => setState(() => _selectedTrend = 'up')),
              chip('下跌', selected: _selectedTrend == 'down',
                  color: Colors.redAccent,
                  onTap: () => setState(() => _selectedTrend = 'down')),
              chip('持平', selected: _selectedTrend == 'flat',
                  color: Colors.amber,
                  onTap: () => setState(() => _selectedTrend = 'flat')),
            ]),
            const SizedBox(height: 8),
            chipRow([
              chip('最近更新', selected: _sortBy == '最近更新',
                  onTap: () => setState(() => _sortBy = '最近更新')),
              chip('涨幅最大', selected: _sortBy == '涨幅最大',
                  onTap: () => setState(() => _sortBy = '涨幅最大')),
              chip('降幅最大', selected: _sortBy == '降幅最大',
                  onTap: () => setState(() => _sortBy = '降幅最大')),
              chip('价格最高', selected: _sortBy == '价格最高',
                  onTap: () => setState(() => _sortBy = '价格最高')),
              chip('价格最低', selected: _sortBy == '价格最低',
                  onTap: () => setState(() => _sortBy = '价格最低')),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewTable(List<_BasketRow> rows) {
    return _buildGlassCard(
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(color: Colors.white12, height: 1),
            InkWell(
              onTap: () async {
                final navigator = Navigator.of(context);
                final result = await navigator.push<String>(
                  MaterialPageRoute(
                      builder: (_) => StoreDetailScreen(storeItem: rows[i].item)),
                );
                if (result != null &&
                    result.startsWith('edit_') &&
                    context.mounted) {
                  navigator.pop(result);
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(rows[i].item.name,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                          const SizedBox(height: 3),
                          Text(
                            [
                              if ((rows[i].item.extras['basketTag']?.toString() ?? '')
                                  .isNotEmpty)
                                '🏷 ${rows[i].item.extras['basketTag']}',
                              if ((rows[i].item.extras['origin']?.toString() ?? '')
                                  .isNotEmpty)
                                '📍 ${rows[i].item.extras['origin']}',
                              if (rows[i].lastChannel.isNotEmpty)
                                '🛒 ${rows[i].lastChannel}',
                              '${rows[i].checkinCount} 次',
                            ].join(' · '),
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white54),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '¥${_fmtPrice(rows[i].latestPrice)}/${_unitOf(rows[i].item)}',
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF10B981)),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 4,
                          children: [
                            _trendBadge(rows[i].changePrev, '较上次'),
                            if (rows[i].changeMonth != null)
                              _trendBadge(rows[i].changeMonth, '较上月'),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _trendBadge(double? change, String prefix) {
    if (change == null) return const SizedBox.shrink();
    final up = change > 0.001;
    final down = change < -0.001;
    final color = up
        ? Colors.redAccent
        : (down ? const Color(0xFF10B981) : Colors.amber);
    final icon = up ? '▲' : (down ? '▼' : '▬');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(35),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$prefix $icon ${BasketStats.formatPct(change)}',
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildComparisonChart(List<_BasketRow> rows) {
    // 时间范围
    DateTime? minT;
    DateTime? maxT;
    for (final r in rows) {
      for (final p in r.points) {
        final t = p.log.timestamp;
        if (minT == null || t.isBefore(minT)) minT = t;
        if (maxT == null || t.isAfter(maxT)) maxT = t;
      }
    }
    final spanMs = (minT != null && maxT != null && maxT.isAfter(minT))
        ? maxT.difference(minT).inMilliseconds
        : 0;

    final bars = <LineChartBarData>[];
    var minY = double.infinity;
    var maxY = double.negativeInfinity;
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final color = _palette[i % _palette.length];
      final first = r.points.first.price;
      final spots = <FlSpot>[
        for (final p in r.points)
          FlSpot(
            spanMs > 0
                ? (p.log.timestamp.difference(minT!).inMilliseconds /
                        spanMs)
                    .clamp(0.0, 1.0)
                : 0.5,
            _normalize ? (first > 0 ? p.price / first * 100 : 0) : p.price,
          ),
      ];
      for (final s in spots) {
        if (s.y < minY) minY = s.y;
        if (s.y > maxY) maxY = s.y;
      }
      bars.add(LineChartBarData(
        spots: spots,
        color: color,
        barWidth: 2,
        isCurved: spots.length > 2,
        dotData: FlDotData(
          show: spots.length == 1,
          getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
              radius: 3, color: color, strokeWidth: 0, strokeColor: color),
        ),
        belowBarData: BarAreaData(show: false),
      ));
    }
    if (minY == double.infinity) minY = 0;
    if (maxY == double.negativeInfinity) maxY = 1;
    if (maxY == minY) {
      maxY += 1;
      minY -= 1;
    }
    final yPad = (maxY - minY) * 0.12;
    minY -= yPad;
    maxY += yPad;
    final yInterval = (maxY - minY) / 4;

    return _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('全部商品价格走势对比',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                ),
                const Text('涨幅归一化',
                    style: TextStyle(fontSize: 11, color: Colors.white54)),
                Switch(
                  value: _normalize,
                  activeThumbColor: const Color(0xFF10B981),
                  onChanged: (v) => setState(() => _normalize = v),
                ),
              ],
            ),
            Text(
              _normalize
                  ? '各商品以首次记录价为 100 点，X 轴按时间归一化，直观对比涨跌幅'
                  : 'X 轴按时间归一化，可直接对比不同单位商品的实际价格走势',
              style: const TextStyle(fontSize: 10, color: Colors.white38),
            ),
            const SizedBox(height: 12),
            if (rows.length > 1) ...[
              Wrap(
                spacing: 10,
                runSpacing: 4,
                children: [
                  for (var i = 0; i < rows.length; i++)
                    _legendItem(
                        _palette[i % _palette.length], rows[i].item.name),
                ],
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: 1,
                  minY: minY,
                  maxY: maxY,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (v) =>
                        const FlLine(color: Colors.white12, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles:
                        const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles:
                        const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 46,
                        interval: yInterval,
                        getTitlesWidget: (value, meta) => Text(
                          _normalize
                              ? value.toStringAsFixed(0)
                              : value.toStringAsFixed(
                                  value.abs() >= 100 ? 0 : 1),
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
                          if (spanMs <= 0 || minT == null) {
                            return const SizedBox.shrink();
                          }
                          final t = minT.add(
                              Duration(milliseconds: (value * spanMs).round()));
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              DateFormat('yy-MM-dd').format(t),
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
                      getTooltipItems: (spots) {
                        final sorted = [...spots]
                          ..sort((a, b) => b.y.compareTo(a.y));
                        return sorted.take(6).map((s) {
                          final t = minT!.add(
                              Duration(milliseconds: (s.x * spanMs).round()));
                          final name = (s.barIndex >= 0 &&
                                  s.barIndex < rows.length)
                              ? rows[s.barIndex].item.name
                              : '';
                          return LineTooltipItem(
                            '$name\n'
                            '${DateFormat('yyyy-MM-dd').format(t)} · '
                            '${s.y.toStringAsFixed(2)}',
                            const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold),
                          );
                        }).toList();
                      },
                    ),
                  ),
                  lineBarsData: bars,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendItem(Color color, String name) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(name,
            style: const TextStyle(fontSize: 10, color: Colors.white70),
            overflow: TextOverflow.ellipsis),
      ],
    );
  }

  Widget _buildMonthlyBarChart(List<_BasketRow> rows) {
    final agg = <String, List<double>>{};
    for (final r in rows) {
      for (final p in r.points) {
        agg.putIfAbsent(_monthKey(p.log.timestamp), () => []).add(p.price);
      }
    }
    final monthKeys = agg.keys.toList()..sort();
    final avgs = [
      for (final k in monthKeys)
        agg[k]!.reduce((a, b) => a + b) / agg[k]!.length,
    ];
    if (monthKeys.isEmpty) return _buildEmptyCard('暂无月份数据');
    final maxV = avgs.reduce((a, b) => a > b ? a : b) * 1.15;
    final label = _selectedTag == '全部' ? '全部果蔬分类' : _selectedTag;

    return _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$label · 月度均价（单位口径混用，仅供参考）',
                style: const TextStyle(fontSize: 12, color: Colors.white54)),
            const SizedBox(height: 12),
            SizedBox(
              height: 190,
              child: BarChart(
                BarChartData(
                  maxY: maxV,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (v) =>
                        const FlLine(color: Colors.white12, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles:
                        const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles:
                        const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) => Text(
                          value.toStringAsFixed(value.abs() >= 10 ? 0 : 1),
                          style: const TextStyle(
                              fontSize: 9, color: Colors.white38),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 26,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= monthKeys.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              monthKeys[i].substring(2),
                              style: const TextStyle(
                                  fontSize: 9, color: Colors.white38),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => const Color(0xFF1E293B),
                      getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                          BarTooltipItem(
                        '${monthKeys[group.x]}\n均价 ¥${rod.toY.toStringAsFixed(2)}',
                        const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < monthKeys.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: avgs[i],
                            width: 18,
                            borderRadius: BorderRadius.circular(4),
                            color: const Color(0xFF10B981).withAlpha(200),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRankingList(List<_BasketRow> rows) {
    final ranked = rows.where((r) => r.changePrev != null).toList()
      ..sort((a, b) => b.changePrev!.compareTo(a.changePrev!));
    if (ranked.isEmpty) {
      return _buildEmptyCard('暂无对比数据（至少 2 次打卡才能计算涨跌）');
    }
    final top = ranked.take(8).toList();
    return _buildGlassCard(
      child: Column(
        children: [
          for (int i = 0; i < top.length; i++) ...[
            if (i > 0) const Divider(color: Colors.white12, height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: top[i].changePrev! > 0
                          ? Colors.redAccent.withAlpha(30)
                          : const Color(0xFF10B981).withAlpha(30),
                      shape: BoxShape.circle,
                    ),
                    child: Text('${i + 1}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: top[i].changePrev! > 0
                                ? Colors.redAccent
                                : const Color(0xFF10B981))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(top[i].item.name,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white),
                        overflow: TextOverflow.ellipsis),
                  ),
                  Text(
                    '¥${_fmtPrice(top[i].latestPrice)}',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.white54),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: (top[i].changePrev! > 0
                              ? Colors.redAccent
                              : const Color(0xFF10B981))
                          .withAlpha(35),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      BasketStats.formatPct(top[i].changePrev),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: top[i].changePrev! > 0
                              ? Colors.redAccent
                              : const Color(0xFF10B981)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BasketRow {
  final StoreItem item;
  final List<({StoreLog log, double price})> points;
  final double latestPrice;
  final DateTime latestTime;
  final double? changePrev;
  final double? changeMonth;
  final int checkinCount;
  final String lastChannel;

  const _BasketRow({
    required this.item,
    required this.points,
    required this.latestPrice,
    required this.latestTime,
    required this.changePrev,
    required this.changeMonth,
    required this.checkinCount,
    required this.lastChannel,
  });
}
