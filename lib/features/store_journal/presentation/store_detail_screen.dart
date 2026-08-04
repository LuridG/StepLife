import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../../../core/export_import/store_exporter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/export_import/bill_parser.dart';
import '../../../core/settings/settings_provider.dart';
import '../../../core/export_import/store_importer.dart';
import '../../../core/export_import/import_preview_screen.dart';
import '../../../core/utils/map_launcher.dart';
import '../domain/store_models.dart';
import '../domain/life_templates.dart';
import '../providers/store_provider.dart';
import '../utils/basket_stats.dart';
import 'store_checkin_dialog.dart';

/// 打卡历史筛选条件：字段（时间/金额）+ 操作符 + 值，多个条件 AND 组合
class LogFilterCondition {
  LogFilterCondition({
    required this.field,
    required this.op,
    this.time,
    this.cost,
  });

  final String field; // 'time' | 'cost'
  final String op; // = > >= < <=
  final DateTime? time;
  final double? cost;

  String get label {
    if (field == 'time') {
      final t = time;
      if (t == null) return '时间 $op ?';
      return '时间 $op ${DateFormat('yyyy-MM-dd HH:mm').format(t)}';
    }
    final v = cost;
    return '金额 $op ${v == null ? '?' : v.toStringAsFixed(2)}';
  }

  /// 该条件是否命中一条打卡（时间比较对齐到分钟，金额 = 用误差 0.005）
  bool matches(StoreLog l) {
    if (field == 'time') {
      final t = time;
      if (t == null) return true;
      final lt = DateTime(l.timestamp.year, l.timestamp.month,
          l.timestamp.day, l.timestamp.hour, l.timestamp.minute);
      final cmp = lt.compareTo(t);
      switch (op) {
        case '=':
          return cmp == 0;
        case '>':
          return cmp > 0;
        case '>=':
          return cmp >= 0;
        case '<':
          return cmp < 0;
        case '<=':
          return cmp <= 0;
      }
      return true;
    }
    final c = l.cost;
    final v = cost;
    if (c == null || v == null) return false;
    switch (op) {
      case '=':
        return (c - v).abs() < 0.005;
      case '>':
        return c > v;
      case '>=':
        return c >= v;
      case '<':
        return c < v;
      case '<=':
        return c <= v;
    }
    return true;
  }
}

/// 老数据/非模板字段的兜底中文标签（避免详情页直接显示英文 key）
const kLogExtrasLabelFallback = <String, String>{
  'qty': '数量',
  'price': '单价',
  'channel': '购买渠道',
  'brand': '品牌',
  'quality': '新鲜度/品质',
  'note': '备注',
  'unit': '单位',
  'origin': '产地/品牌',
  'basketTag': '果蔬分类',
  'total': '总价',
  'totalAmount': '总价',
  'cost': '消费总额',
  'sku': '规格型号',
  'refPrice': '参考价（元）',
  'buyReason': '购买理由',
  'actualCost': '实付金额（元）',
  'detail': '购买明细',
  'experience': '使用体验',
  'episodesWatched': '已看集数',
  'platform': '观看平台',
  'genre': '题材',
  'year': '上映年份',
  'director': '导演',
  'duration': '片长',
};

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
  final ImagePicker _picker = ImagePicker();

  /// 菜篮子品牌筛选（'全部' 或具体品牌）
  String _basketBrand = '全部';

  /// 打卡历史：紧凑视图开关
  bool _compactLogs = false;

  /// 打卡历史筛选条件（多个条件 AND 组合，空=无筛选）
  final List<LogFilterCondition> _logFilters = [];

  bool get _hasLogFilter => _logFilters.isNotEmpty;

  /// 按多个筛选条件（AND 组合）过滤打卡记录
  List<StoreLog> _applyLogFilters(List<StoreLog> logs) {
    if (_logFilters.isEmpty) return logs;
    return logs.where((l) => _logFilters.every((f) => f.matches(l))).toList();
  }

  Future<void> _showLogFilterSheet(BuildContext context) async {
    var newField = 'time';
    var newOp = '>=';
    var newTime = DateTime.now();
    var newCost = 0.0;
    final costCtrl = TextEditingController();
    final draftFilters = List<LogFilterCondition>.of(_logFilters);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111C38),
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('筛选打卡记录（可叠加多个条件）',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 12),
                if (draftFilters.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('尚未添加条件，点击下方「添加条件」设置。',
                        style: TextStyle(fontSize: 12, color: Colors.white38)),
                  )
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var i = 0; i < draftFilters.length; i++)
                        InputChip(
                          label: Text(draftFilters[i].label, style: const TextStyle(fontSize: 11.5, color: Colors.white)),
                          deleteIcon: const Icon(Icons.close, size: 15, color: Colors.white54),
                          backgroundColor: const Color(0xFF10B981).withAlpha(25),
                          side: const BorderSide(color: Color(0xFF10B981)),
                          onDeleted: () => setSheet(() => draftFilters.removeAt(i)),
                        ),
                    ],
                  ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('添加条件', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white70)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final f in const <(String, String)>[('time', '时间'), ('cost', '金额')])
                            ChoiceChip(
                              label: Text(f.$2, style: const TextStyle(fontSize: 12)),
                              selected: newField == f.$1,
                              selectedColor: const Color(0xFF10B981).withAlpha(70),
                              backgroundColor: Colors.white10,
                              labelStyle: TextStyle(color: newField == f.$1 ? Colors.white : Colors.white70),
                              onSelected: (_) => setSheet(() => newField = f.$1),
                            ),
                          for (final o in const ['=', '>', '>=', '<', '<='])
                            ChoiceChip(
                              label: Text(o, style: const TextStyle(fontSize: 12)),
                              selected: newOp == o,
                              selectedColor: const Color(0xFF10B981).withAlpha(70),
                              backgroundColor: Colors.white10,
                              labelStyle: TextStyle(color: newOp == o ? Colors.white : Colors.white70),
                              onSelected: (_) => setSheet(() => newOp = o),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (newField == 'time')
                        OutlinedButton.icon(
                          icon: const Icon(Icons.event, size: 16),
                          label: Text(DateFormat('yyyy-MM-dd HH:mm').format(newTime),
                              style: const TextStyle(fontSize: 12.5, color: Colors.white70)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: const BorderSide(color: Colors.white24),
                          ),
                          onPressed: () async {
                            final d = await showDatePicker(
                              context: ctx,
                              initialDate: newTime,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (d == null || !ctx.mounted) return;
                            final t = await showTimePicker(
                              context: ctx,
                              initialTime: TimeOfDay.fromDateTime(newTime),
                            );
                            if (t == null) return;
                            setSheet(() => newTime =
                                DateTime(d.year, d.month, d.day, t.hour, t.minute));
                          },
                        )
                      else
                        TextField(
                          controller: costCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: '输入金额，如 26.5',
                            hintStyle: TextStyle(color: Colors.white38),
                            isDense: true,
                          ),
                          onChanged: (v) => newCost = double.tryParse(v.trim()) ?? 0,
                        ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonal(
                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981).withAlpha(50)),
                          onPressed: () => setSheet(() {
                            draftFilters.add(LogFilterCondition(
                              field: newField,
                              op: newOp,
                              time: newField == 'time' ? newTime : null,
                              cost: newField == 'cost' ? newCost : null,
                            ));
                            costCtrl.clear();
                          }),
                          child: const Text('＋ 添加条件', style: TextStyle(fontSize: 12.5)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        setState(() => _logFilters.clear());
                      },
                      child: const Text('清除全部', style: TextStyle(color: Colors.white54)),
                    ),
                    const Spacer(),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                      onPressed: () {
                        Navigator.pop(ctx);
                        setState(() {
                          _logFilters.clear();
                          _logFilters.addAll(draftFilters);
                        });
                      },
                      child: Text(draftFilters.isEmpty ? '关闭' : '应用筛选（${draftFilters.length} 个）'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    costCtrl.dispose();
  }
  /// 打卡统计：汇总当前（筛选后）打卡列表的各类信息，按模板类型差异化展示
  void _showLogStatsSheet(BuildContext context, List<StoreLog> logs, String templateKey) {
    if (logs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('当前没有可统计的打卡记录'),
      ));
      return;
    }
    final costs = logs.map((l) => l.cost).whereType<double>().toList();
    final total = costs.fold<double>(0, (s, c) => s + c);
    final avg = costs.isEmpty ? null : total / costs.length;
    double? maxC;
    double? minC;
    for (final c in costs) {
      maxC = maxC == null || c > maxC ? c : maxC;
      minC = minC == null || c < minC ? c : minC;
    }
    final sorted = [...logs]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final byMonth = <String, int>{};
    final byVisitor = <String, int>{};
    final byMenu = <String, int>{};
    for (final l in logs) {
      final mk = DateFormat('yyyy-MM').format(l.timestamp);
      byMonth[mk] = (byMonth[mk] ?? 0) + 1;
      for (final v in l.visitorNames) {
        if (v.trim().isEmpty) continue;
        byVisitor[v.trim()] = (byVisitor[v.trim()] ?? 0) + 1;
      }
      for (final m in l.menuNames) {
        if (m.trim().isEmpty) continue;
        byMenu[m.trim()] = (byMenu[m.trim()] ?? 0) + 1;
      }
    }
    final months = byMonth.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final visitors = byVisitor.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final menus = byMenu.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // ---- 模板类型专属统计 ----
    final typeBlocks = <Widget>[];
    switch (templateKey) {
      case 'dining':
        // 人均消费（按同行人数平均）
        var personCost = 0.0;
        var personCount = 0;
        for (final l in logs) {
          final n = l.visitorNames.where((v) => v.trim().isNotEmpty).length;
          final c = l.cost;
          if (n > 0 && c != null) {
            personCost += c;
            personCount += n;
          }
        }
        if (personCount > 0) {
          typeBlocks.add(_statsSectionTitle('人均消费'));
          typeBlocks.add(_statChip('¥${_fmtPrice(personCost / personCount)}', '按同行人数平均'));
        }
        typeBlocks.addAll(_distWidgets('结算平台', _collectMultiExtras(logs, 'platform')));
      case 'movie':
        typeBlocks.addAll(_distWidgets('观看平台', _collectMultiExtras(logs, 'platform')));
        typeBlocks.addAll(_distWidgets('媒体类型', _collectSingles(logs, 'mediaType')));
        var watched = 0;
        var totalEps = 0;
        for (final l in logs) {
          watched += _numFrom(l.extras['watchedEpisodes']);
          totalEps += _numFrom(l.extras['totalEpisodes']);
        }
        if (watched > 0 || totalEps > 0) {
          typeBlocks.add(_statsSectionTitle('集数进度'));
          typeBlocks.add(_statChip(totalEps > 0
              ? '$watched / $totalEps 集'
              : '$watched 集',
              '累计已看 / 总集数'));
        }
      case 'snack':
        typeBlocks.addAll(_distWidgets('品牌分布', _collectSingles(logs, 'brand')));
        typeBlocks.addAll(_distWidgets('零食分类', _collectSingles(logs, 'snackTag')));
      case 'book':
        final progresses = logs.reversed
            .map((l) => l.extras['progress']?.toString().trim() ?? '')
            .where((s) => s.isNotEmpty)
            .take(3)
            .toList();
        if (progresses.isNotEmpty) {
          typeBlocks.add(_statsSectionTitle('最近阅读进度'));
          typeBlocks.addAll(
              progresses.map((p) => _statChip(p, '')));
        }
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111C38),
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.insights, color: Color(0xFF10B981), size: 20),
                    const SizedBox(width: 8),
                    const Text('打卡统计',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    const Spacer(),
                    const Text('基于当前筛选结果', style: TextStyle(fontSize: 10.5, color: Colors.white38)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                    '共 ${logs.length} 次 · ${DateFormat('yyyy-MM-dd').format(sorted.first.timestamp)} 至 ${DateFormat('yyyy-MM-dd').format(sorted.last.timestamp)}',
                    style: const TextStyle(fontSize: 12, color: Colors.white54)),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _statsMetric('总金额', '¥${_fmtPrice(total)}'),
                    _statsMetric('平均', avg == null ? '—' : '¥${_fmtPrice(avg)}'),
                    _statsMetric('最高', maxC == null ? '—' : '¥${_fmtPrice(maxC)}'),
                    _statsMetric('最低', minC == null ? '—' : '¥${_fmtPrice(minC)}'),
                  ],
                ),
                ...typeBlocks,
                if (months.isNotEmpty) ...[
                  _statsSectionTitle('按月分布'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final m in months)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withAlpha(25),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF10B981).withAlpha(60)),
                          ),
                          child: Text('${m.key} · ${m.value}次',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF86EFAC))),
                        ),
                    ],
                  ),
                ],
                if (visitors.isNotEmpty) ...[
                  _statsSectionTitle('成员分布'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final v in visitors)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('${v.key} · ${v.value}次',
                              style: const TextStyle(fontSize: 11, color: Colors.white70)),
                        ),
                    ],
                  ),
                ],
                if (menus.isNotEmpty) ...[
                  _statsSectionTitle('点菜频次'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final m in menus.take(12))
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withAlpha(20),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFF59E0B).withAlpha(50)),
                          ),
                          child: Text('${m.key} ×${m.value}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFFFCD34D))),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statsSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(title,
          style: const TextStyle(fontSize: 12.5, color: Colors.white70, fontWeight: FontWeight.w600)),
    );
  }

  Widget _statChip(String text, String sub) {
    return Padding(
      padding: const EdgeInsets.only(right: 6, bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
            if (sub.isNotEmpty)
              Text(sub, style: const TextStyle(fontSize: 10.5, color: Colors.white38)),
          ],
        ),
      ),
    );
  }

  /// 统计分布：标题 + 名称×次数 标签
  List<Widget> _distWidgets(String title, List<String> values) {
    final counts = <String, int>{};
    for (final v in values) {
      if (v.trim().isEmpty) continue;
      counts[v.trim()] = (counts[v.trim()] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (sorted.isEmpty) return const [];
    return [
      _statsSectionTitle(title),
      const SizedBox(height: 2),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final e in sorted)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('${e.key} · ${e.value}次',
                  style: const TextStyle(fontSize: 11, color: Colors.white70)),
            ),
        ],
      ),
    ];
  }

  List<String> _collectSingles(List<StoreLog> logs, String key) {
    final out = <String>[];
    for (final l in logs) {
      final v = (l.extras[key]?.toString() ?? '').trim();
      if (v.isNotEmpty) out.add(v);
    }
    return out;
  }

  /// 多选字段（platform 等）可能是 JSON 数组字符串，也可能是分隔文本
  List<String> _collectMultiExtras(List<StoreLog> logs, String key) {
    final out = <String>[];
    for (final l in logs) {
      final raw = l.extras[key];
      if (raw == null) continue;
      final s = raw.toString().trim();
      if (s.isEmpty) continue;
      if (s.startsWith('[')) {
        try {
          final d = jsonDecode(s);
          if (d is List) {
            out.addAll(d.map((e) => e.toString().trim()).where((e) => e.isNotEmpty));
            continue;
          }
        } catch (_) {}
      }
      out.addAll(s.split(RegExp(r'[,，、]')).map((e) => e.trim()).where((e) => e.isNotEmpty));
    }
    return out;
  }

  int _numFrom(Object? raw) {
    if (raw == null) return 0;
    final m = RegExp(r'\d+').firstMatch(raw.toString());
    return m == null ? 0 : int.tryParse(m.group(0)!) ?? 0;
  }

  Widget _statsMetric(String label, String value) {
    return Container(
      width: (MediaQuery.of(context).size.width - 56) / 4,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(fontSize: 10.5, color: Colors.white54)),
        ],
      ),
    );
  }

  Future<void> _handleExportCategory(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final data = await StoreExporter.buildExportData(category: widget.storeItem.category);
      final file = await StoreExporter.writeExportFile(data, category: widget.storeItem.category);
      await StoreExporter.copyToDocuments(file);
      await StoreExporter.shareFile(file);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(
        backgroundColor: Color(0xFF10B981),
        content: Text('已导出该分类（JSON）'),
      ));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        backgroundColor: const Color(0xFFEF4444),
        content: Text('导出失败：$e'),
      ));
    }
  }

  Future<void> _handleImportLogs(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        dialogTitle: '选择打卡记录文件',
      );
      if (picked == null || picked.files.isEmpty) return;
      final path = picked.files.single.path;
      if (path == null) return;
      final content = await File(path).readAsString();
      final draft = StoreImporter.parseLogsOnly(
        content,
        targetStoreId: widget.storeItem.id ?? 0,
        targetStoreName: widget.storeItem.name,
        targetCategory: widget.storeItem.category,
      );
      if (!context.mounted) return;
      final result = await Navigator.of(context).push<ImportResult>(
        MaterialPageRoute(builder: (_) => ImportPreviewScreen(draft: draft)),
      );
      if (result != null && context.mounted) {
        await context.read<StoreProvider>().loadData();
        messenger.showSnackBar(SnackBar(
          backgroundColor: const Color(0xFF10B981),
          content: Text('已导入 ${result.createdLogs + result.mergedLogs} 条打卡记录'),
        ));
      }
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(
        backgroundColor: const Color(0xFFEF4444),
        content: Text('导入失败：$e'),
      ));
    }
  }

  Future<void> _handleImportBill(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final settings = context.read<SettingsProvider>();
      if (settings.deepseekApiKey.trim().isEmpty) {
        messenger.showSnackBar(const SnackBar(
          backgroundColor: Color(0xFFEF4444),
          content: Text('请先在设置中心配置 DeepSeek API Key 后使用账单导入'),
        ));
        return;
      }
      final source = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: const Color(0xFF111C38),
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (BillParser.isOcrSupported)
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined, color: Colors.white70),
                  title: const Text('从相册选择账单图片（内置 OCR）', style: TextStyle(color: Colors.white)),
                  onTap: () => Navigator.pop(ctx, 'image'),
                ),
              ListTile(
                leading: const Icon(Icons.keyboard_outlined, color: Colors.white70),
                title: const Text('粘贴 OCR 文字（AI 识别）', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, 'paste'),
              ),
            ],
          ),
        ),
      );
      if (source == null || !context.mounted) return;

      String rawText;
      if (source == 'image') {
        final picked = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 2400);
        if (picked == null) return;
        messenger.showSnackBar(const SnackBar(content: Text('正在 OCR 识别账单…')));
        try {
          rawText = await BillParser.ocrImage(picked.path);
        } on BillOcrUnavailableException {
          messenger.showSnackBar(const SnackBar(
            content: Text('当前设备不支持离线 OCR，已切换为粘贴账单文字'),
          ));
          if (!context.mounted) return;
          rawText = await _askPasteText(context);
          if (rawText.isEmpty) return;
        } catch (e) {
          messenger.showSnackBar(SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text('OCR 识别失败：$e'),
          ));
          return;
        }
      } else {
        rawText = await _askPasteText(context);
        if (rawText.isEmpty) return;
      }
      if (!context.mounted) return;

      // 敏感词过滤 + 人工复核（OCR 文本送 AI 前）
      final redacted = BillParser.redactSensitive(rawText, settings.billSensitiveKeywords);
      final reviewed = await _askReviewRedactedText(context, redacted.text, redacted.removed);
      if (reviewed == null) return;
      if (reviewed.trim().isEmpty) {
        messenger.showSnackBar(const SnackBar(
          backgroundColor: Color(0xFFEF4444),
          content: Text('账单文字为空，已取消导入'),
        ));
        return;
      }
      if (!context.mounted) return;

      messenger.showSnackBar(const SnackBar(content: Text('正在整理账单内容…')));
      final result = await BillParser.structure(
        rawText: reviewed,
        storeName: widget.storeItem.name,
        category: widget.storeItem.category,
        apiKey: settings.deepseekApiKey,
      );
      if (result.records.isEmpty) {
        messenger.showSnackBar(const SnackBar(
          backgroundColor: Color(0xFFEF4444),
          content: Text('未能从账单中识别出任何消费记录'),
        ));
        return;
      }
      final draft = BillParser.toDraft(
        result,
        storeId: widget.storeItem.id ?? 0,
        storeName: widget.storeItem.name,
        category: widget.storeItem.category,
      );
      if (!context.mounted) return;
      final importResult = await Navigator.of(context).push<ImportResult>(
        MaterialPageRoute(builder: (_) => ImportPreviewScreen(draft: draft)),
      );
      if (importResult != null && context.mounted) {
        await context.read<StoreProvider>().loadData();
        messenger.showSnackBar(SnackBar(
          backgroundColor: const Color(0xFF10B981),
          content: Text('已导入 ${importResult.createdLogs + importResult.mergedLogs} 条消费记录'),
        ));
      }
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(
        backgroundColor: const Color(0xFFEF4444),
        content: Text('账单导入失败：$e'),
      ));
    }
  }

  Future<String> _askPasteText(BuildContext context) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('粘贴 OCR 文字'),
        backgroundColor: const Color(0xFF111C38),
        content: TextField(
          controller: ctrl,
          maxLines: 8,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: '粘贴 OCR 识别出的账单文字（可含多笔消费）',
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('继续')),
        ],
      ),
    );
    return ok == true ? ctrl.text.trim() : '';
  }

  Future<String?> _askReviewRedactedText(
    BuildContext context,
    String text,
    int removed,
  ) async {
    final ctrl = TextEditingController(text: text);
    final ok = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('复核账单文字'),
        backgroundColor: const Color(0xFF111C38),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                removed > 0
                    ? '已自动删除 $removed 处敏感信息（如交易单号/商户单号），可继续手动删除内容。'
                    : '未发现默认敏感词，可直接删除不需要的内容后确认。',
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                maxLines: 12,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  hintText: '确认无误后点击「确认，交给 AI 整理」',
                  hintStyle: TextStyle(color: Colors.white24),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('确认，交给 AI 整理'),
          ),
        ],
      ),
    );
    return ok;
  }

  void _confirmDeleteLog(BuildContext context, StoreLog log) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除此次打卡记录?'),
        content: Text('打卡时间: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(log.timestamp)}\n消费: ¥${log.cost?.toStringAsFixed(1) ?? "0"}'),
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
    final filteredLogs = _applyLogFilters(logs);
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
            ? filteredLogs
            : filteredLogs.where((l) => BasketStats.brandLabel(l) == _basketBrand).toList())
        : const <StoreLog>[];
    final basketPoints = isBasket
        ? BasketStats.pricePoints(visibleBasketLogs)
        : const <({StoreLog log, double price})>[];
    final basketLatest = isBasket ? BasketStats.latestPrice(visibleBasketLogs) : null;
    final basketUnitRaw = widget.storeItem.extras['unit'];
    final basketUnit = (basketUnitRaw == null || basketUnitRaw.toString().trim().isEmpty)
        ? '斤'
        : (basketUnitRaw is num
            ? (basketUnitRaw == basketUnitRaw.roundToDouble()
                ? basketUnitRaw.toInt().toString()
                : basketUnitRaw.toString())
            : basketUnitRaw.toString());
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
      for (final f in [
        ...tpl.checkinFields,
        ...(cat?.extraFields ?? const []).map((m) => TemplateField.fromJson(m)),
        ...itemFields,
      ])
        f.key: f.label,
      ...kLogExtrasLabelFallback,
    };
    final logFieldTypes = {
      for (final f in [...tpl.checkinFields, ...(cat?.extraFields ?? const []).map((m) => TemplateField.fromJson(m))])
        f.key: f.type,
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
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white70),
            tooltip: '更多',
            color: const Color(0xFF0F172A),
            onSelected: (v) {
              if (v == 'export_category') {
                _handleExportCategory(context);
              } else if (v == 'import_logs') {
                _handleImportLogs(context);
              } else if (v == 'import_bill') {
                _handleImportBill(context);
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem<String>(
                value: 'export_category',
                child: const Row(
                  children: [
                    Icon(Icons.folder_shared_outlined, size: 16, color: Colors.white70),
                    SizedBox(width: 8),
                    Text('导出该分类', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'import_logs',
                child: const Row(
                  children: [
                    Icon(Icons.file_upload_outlined, size: 16, color: Colors.white70),
                    SizedBox(width: 8),
                    Text('导入打卡记录（JSON）', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'import_bill',
                child: const Row(
                  children: [
                    Icon(Icons.receipt_long_outlined, size: 16, color: Colors.white70),
                    SizedBox(width: 8),
                    Text('导入账单（OCR+AI）', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
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
                                    SizedBox(width: 92, child: Text(kLogExtrasLabelFallback[en.key] ?? en.key, style: const TextStyle(fontSize: 12, color: Colors.white54))),
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

                // 打卡履约历史时间线 (Timeline)
                Row(
                  children: [
                    const Icon(Icons.history, color: Color(0xFF10B981), size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('打卡历史',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: '筛选打卡',
                      icon: Icon(Icons.filter_list,
                          size: 20,
                          color: _hasLogFilter ? const Color(0xFF10B981) : Colors.white54),
                      onPressed: () => _showLogFilterSheet(context),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: '打卡统计',
                      icon: const Icon(Icons.insights_outlined, size: 20, color: Colors.white54),
                      onPressed: () => _showLogStatsSheet(context, filteredLogs, tpl.key),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: _compactLogs ? '切换为卡片视图' : '切换为紧凑视图',
                      icon: Icon(_compactLogs ? Icons.view_agenda_outlined : Icons.view_list_outlined,
                          size: 20,
                          color: Colors.white54),
                      onPressed: () => setState(() => _compactLogs = !_compactLogs),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                filteredLogs.isEmpty
                    ? _buildGlassCard(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Center(
                            child: Text(
                              _hasLogFilter
                                  ? '没有符合筛选条件的打卡记录，可点右上角筛选按钮调整。'
                                  : '暂无打卡记录，点击主页【⚡ 记一次打卡】添加。',
                              style: const TextStyle(color: Colors.white54, fontSize: 13),
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filteredLogs.length,
                        itemBuilder: (ctx, idx) {
                          final log = filteredLogs[idx];
                          final timeStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(log.timestamp);
                          if (_compactLogs) return _buildCompactLogTile(log, timeStr);

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
                                      ..._formatLogExtras(log, logFieldLabels, logFieldTypes, isBasket),
                                    ],
                                    if (log.cost != null && log.cost! > 0) ...[
                                      const SizedBox(height: 2),
                                      Text('🧾 消费总额: ¥${_fmtPrice(log.cost!)}',
                                          style: const TextStyle(fontSize: 12, color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
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
  List<Widget> _formatLogExtras(
      StoreLog log, Map<String, String> labels, Map<String, TemplateFieldType> types, bool isBasketLog) {
    final widgets = <Widget>[];
    final unitRaw = widget.storeItem.extras['unit'];
    final unit = (unitRaw == null || unitRaw.toString().trim().isEmpty)
        ? '斤'
        : (unitRaw is num
            ? (unitRaw == unitRaw.roundToDouble()
                ? unitRaw.toInt().toString()
                : unitRaw.toString())
            : unitRaw.toString());
    log.extras.forEach((key, value) {
      if (value == null) return;
      final str = value.toString();
      if (str.isEmpty || str == 'false') return;
      var display = value == true ? '是' : str;
      var label = labels[key] ?? key;
      final type = types[key];
      if (type == TemplateFieldType.rating && value is num) {
        display = '⭐ ${value.toStringAsFixed(1)}';
      } else if (value is List) {
        display = value.map((e) => e.toString()).where((e) => e.isNotEmpty).join(' / ');
      }
      if (isBasketLog && key == 'price' && value is num) {
        label = '单价';
        display = '${_fmtPrice(value.toDouble())}元/$unit';
      }
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

  /// 紧凑打卡条目：单行时间+金额+摘要，编辑/删除用小图标，适合窄屏
  Widget _buildCompactLogTile(StoreLog log, String timeStr) {
    final brand = (log.extras['brand']?.toString() ?? '').trim();
    final parts = <String>[
      if (log.memo != null && log.memo!.isNotEmpty) log.memo!,
      if (log.menuNames.isNotEmpty) log.menuNames.join('、'),
    ];
    final summary = parts.join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: _buildGlassCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(timeStr,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white)),
                        ),
                        if (log.cost != null) ...[
                          const SizedBox(width: 8),
                          Text('¥${_fmtPrice(log.cost!)}',
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                        ],
                      ],
                    ),
                    if (summary.isNotEmpty || brand.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          brand.isEmpty ? summary : '$brand · $summary',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: Colors.white54),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, color: Colors.lightBlueAccent, size: 15),
                visualDensity: VisualDensity.compact,
                tooltip: '修改打卡',
                onPressed: () => showDialog(
                  context: context,
                  builder: (ctx) => StoreCheckinDialog(store: widget.storeItem, existingLog: log),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 15),
                visualDensity: VisualDensity.compact,
                onPressed: () => _confirmDeleteLog(context, log),
              ),
            ],
          ),
        ),
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
