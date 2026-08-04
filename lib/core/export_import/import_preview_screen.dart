import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'import_draft.dart';
import 'store_importer.dart';

/// 模拟导入页：全程内存预览（不落库），可勾选/编辑/切换新建或合并，
/// 底部「确认导入」才真正执行备份 + 单事务写入。
class ImportPreviewScreen extends StatefulWidget {
  const ImportPreviewScreen({super.key, required this.draft});

  final ImportDraft draft;

  @override
  State<ImportPreviewScreen> createState() => _ImportPreviewScreenState();
}

class _ImportPreviewScreenState extends State<ImportPreviewScreen> {
  bool _resolving = true;
  bool _busy = false;

  ImportDraft get draft => widget.draft;

  @override
  void initState() {
    super.initState();
    _reresolve();
  }

  Future<void> _reresolve() async {
    setState(() => _resolving = true);
    await StoreImporter.resolve(draft);
    if (mounted) setState(() => _resolving = false);
  }

  Future<void> _changeCategoryStrategy(ImportCategoryDraft c, ImportStrategy s) async {
    c.strategy = s;
    // 分类策略联动其下项目（项目可再单独覆盖）
    for (final it in c.items) {
      it.strategy = s;
    }
    await _reresolve();
  }

  Future<void> _editLog(ImportLogDraft log) async {
    final costCtrl = TextEditingController(text: log.cost?.toString() ?? '');
    final timeCtrl = TextEditingController(
      text: log.timestamp == null
          ? ''
          : DateFormat('yyyy-MM-dd HH:mm:ss').format(log.timestamp!),
    );
    final memoCtrl = TextEditingController(text: log.memo ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑打卡'),
        backgroundColor: const Color(0xFF111C38),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: costCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: '金额（元，可留空）',
                  labelStyle: TextStyle(color: Colors.white54),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: timeCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: '时间（yyyy-MM-dd HH:mm:ss）',
                  labelStyle: TextStyle(color: Colors.white54),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: memoCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: '备注',
                  labelStyle: TextStyle(color: Colors.white54),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved == true && mounted) {
      setState(() {
        final cost = double.tryParse(costCtrl.text.trim());
        var time = DateTime.tryParse(timeCtrl.text.trim());
        time ??= DateFormat('yyyy-MM-dd HH:mm:ss').tryParse(timeCtrl.text.trim());
        time ??= DateFormat('yyyy-MM-dd HH:mm').tryParse(timeCtrl.text.trim());
        if (time != null) {
          time = DateTime(time.year, time.month, time.day, time.hour, time.minute, time.second);
        }
        log.cost = cost;
        log.timestamp = time;
        log.memo = memoCtrl.text.trim().isEmpty ? null : memoCtrl.text.trim();
      });
    }
  }

  Future<void> _confirm() async {
    // 每张打卡必须有完整时间（分钟级），否则要求先在预览中补充
    final missing = draft.categories
        .where((c) => c.selected)
        .expand((c) => c.items)
        .where((i) => i.selected)
        .expand((i) => i.logs)
        .where((l) => l.selected && l.timestamp == null)
        .length;
    if (missing > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFEF4444),
          content: Text('存在缺时间的打卡记录，请点开对应打卡补充时间（yyyy-MM-dd HH:mm:ss）后再导入'),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await StoreImporter.apply(draft);
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFEF4444),
          content: Text('导入失败：$e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('模拟导入预览')),
      body: _resolving
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _summaryCard(),
                const SizedBox(height: 12),
                for (final c in draft.categories) ...[
                  _categoryCard(c),
                  const SizedBox(height: 10),
                ],
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _busy ? null : _confirm,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('确认导入'),
          ),
        ),
      ),
    );
  }

  Widget _summaryCard() {
    final d = draft;
    final logCount = d.totalLogs;
    final itemCount = d.totalItems;
    final catCount = d.totalCategories;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111C38),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '将导入：$catCount 个分类 · $itemCount 个项目 · $logCount 条打卡',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            '以下为预览，可勾选、编辑并确认，确认后才会写入数据；导入前会自动备份当前数据库。',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('打卡策略',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(width: 8),
              _actionTag('全部合并', () => _setAllLogStrategy(ImportStrategy.merge)),
              const SizedBox(width: 6),
              _actionTag('全部新建', () => _setAllLogStrategy(ImportStrategy.create)),
              const Spacer(),
              const Text('可逐条点击标签切换',
                  style: TextStyle(color: Colors.white38, fontSize: 10.5)),
            ],
          ),
        ],
      ),
    );
  }

  void _setAllLogStrategy(ImportStrategy s) {
    setState(() {
      for (final c in draft.categories) {
        for (final it in c.items) {
          for (final l in it.logs) {
            l.strategy = s;
          }
        }
      }
    });
  }

  Widget _categoryCard(ImportCategoryDraft c) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: c.selected,
                onChanged: (v) => setState(() => c.selected = v ?? true),
              ),
              Expanded(
                child: Text(
                  c.resolvedName.isEmpty ? c.name : c.resolvedName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              if (c.lockToTarget) ...[
                const Icon(Icons.lock_outline, size: 14, color: Colors.white38),
                const SizedBox(width: 4),
                const Text('导入到已有分类', style: TextStyle(color: Colors.white38, fontSize: 12)),
              ] else if (c.targetCategoryId != null) ...[
                const Text('策略', style: TextStyle(color: Colors.white38, fontSize: 12)),
                _strategyDropdown(c.strategy, (s) => _changeCategoryStrategy(c, s)),
              ] else
                const Text('新建', style: TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
          for (final it in c.items) _itemTile(it),
          if (c.items.isEmpty)
            const Padding(
              padding: EdgeInsets.only(left: 16),
              child: Text(
                '（该分类下无项目）',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _itemTile(ImportItemDraft it) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: it.selected,
                onChanged: (v) => setState(() => it.selected = v ?? true),
              ),
              Expanded(
                child: Text(
                  it.resolvedName.isEmpty ? it.name : it.resolvedName,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
              if (it.lockToTarget)
                const Text('导入到当前餐厅', style: TextStyle(color: Colors.white38, fontSize: 12))
              else if (it.targetItemId != null)
                _strategyDropdown(it.strategy, (s) async {
                  it.strategy = s;
                  await _reresolve();
                })
              else
                const Text('新建', style: TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
          if (it.targetItemId != null && it.strategy == ImportStrategy.merge)
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 4),
              child: Text(
                '将合并到已有项目',
                style: TextStyle(color: Colors.cyan.shade200, fontSize: 11),
              ),
            ),
          for (final log in it.logs) _logTile(log),
          if (it.logs.isEmpty)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Text(
                '（无打卡记录）',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _logTile(ImportLogDraft log) {
    final time = log.timestamp == null
        ? ''
        : DateFormat('yyyy-MM-dd HH:mm:ss').format(log.timestamp!);
    final cost = log.cost == null ? '' : '¥${log.cost}';
    final memo = log.memo == null ? '' : ' · ${log.memo}';
    return InkWell(
      onTap: () => _editLog(log),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Row(
          children: [
            Checkbox(
              value: log.selected,
              onChanged: (v) => setState(() => log.selected = v ?? true),
            ),
            Expanded(
              child: Row(
                children: [
                  if (log.timestamp == null) ...[
                    const Text('缺时间 ', style: TextStyle(color: Colors.redAccent, fontSize: 12.5)),
                  ],
                  Expanded(
                    child: Text(
                      '$time $cost$memo',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
            _strategyTag(
              log.strategy,
              (s) => setState(() => log.strategy = s),
              small: true,
            ),
            const SizedBox(width: 4),
            const Icon(Icons.edit_outlined, size: 14, color: Colors.white24),
          ],
        ),
      ),
    );
  }

  Widget _actionTag(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.white70)),
      ),
    );
  }

  /// 打卡策略标签：点击在「合并/新建」间切换
  Widget _strategyTag(
    ImportStrategy value,
    ValueChanged<ImportStrategy> onChanged, {
    bool small = false,
  }) {
    final isMerge = value == ImportStrategy.merge;
    return InkWell(
      onTap: () =>
          onChanged(isMerge ? ImportStrategy.create : ImportStrategy.merge),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: small ? 8 : 10,
          vertical: small ? 3 : 5,
        ),
        decoration: BoxDecoration(
          color: isMerge
              ? const Color(0xFF0E7490).withAlpha(70)
              : const Color(0xFFB45309).withAlpha(70),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isMerge
                ? Colors.cyan.shade400.withAlpha(140)
                : Colors.amber.shade400.withAlpha(140),
          ),
        ),
        child: Text(
          isMerge ? '合并' : '新建',
          style: TextStyle(
            fontSize: small ? 10.5 : 12,
            fontWeight: FontWeight.w600,
            color: isMerge ? Colors.cyan.shade100 : Colors.amber.shade100,
          ),
        ),
      ),
    );
  }

  Widget _strategyDropdown(
    ImportStrategy value,
    ValueChanged<ImportStrategy> onChanged,
  ) {
    return DropdownButton<ImportStrategy>(
      value: value,
      underline: const SizedBox.shrink(),
      isDense: true,
      style: const TextStyle(fontSize: 12, color: Colors.white70),
      dropdownColor: const Color(0xFF0F172A),
      items: const [
        DropdownMenuItem(
          value: ImportStrategy.create,
          child: Text('新建'),
        ),
        DropdownMenuItem(
          value: ImportStrategy.merge,
          child: Text('合并'),
        ),
      ],
      onChanged: (s) => s == null ? null : onChanged(s),
    );
  }
}
