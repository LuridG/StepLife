import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/settings/settings_button.dart';
import '../domain/chore_models.dart';
import '../providers/chore_provider.dart';
import '../../../core/utils/number_formatter.dart';
import '../../assistant/presentation/assistant_screen.dart';
import 'chore_detail_screen.dart';

class ChoreTrackerScreen extends StatefulWidget {
  const ChoreTrackerScreen({super.key});

  @override
  State<ChoreTrackerScreen> createState() => _ChoreTrackerScreenState();
}

class _ChoreTrackerScreenState extends State<ChoreTrackerScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  void _showAddChoreDialog() {
    final titleController = TextEditingController();
    final categoryController = TextEditingController(text: '日常家务');
    final unitController = TextEditingController(text: '元');
    bool isQuantifiable = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('新建家务/习惯 Item'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: '家务/习惯名称',
                      hintText: '例: 拖地 / 洗碗 / 买菜记账',
                      prefixIcon: Icon(Icons.task),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: categoryController,
                    decoration: const InputDecoration(
                      labelText: '分类',
                      prefixIcon: Icon(Icons.category),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('启用量化登记', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text('例如: 买菜花了多少钱，量化数值属性'),
                    value: isQuantifiable,
                    activeThumbColor: const Color(0xFF6366F1),
                    onChanged: (val) {
                      setModalState(() => isQuantifiable = val);
                    },
                  ),
                  if (isQuantifiable)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: TextField(
                        controller: unitController,
                        decoration: const InputDecoration(
                          labelText: '数值单位',
                          hintText: '如: 元 / 分钟 / 件',
                          prefixIcon: Icon(Icons.pin),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  titleController.dispose();
                  categoryController.dispose();
                  unitController.dispose();
                  Navigator.of(ctx).pop();
                },
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () {
                  final title = titleController.text.trim();
                  if (title.isNotEmpty) {
                    context.read<ChoreProvider>().addChoreItem(
                          title,
                          category: categoryController.text.trim(),
                          isQuantifiable: isQuantifiable,
                          unit: isQuantifiable ? unitController.text.trim() : '次',
                        );
                  }
                  titleController.dispose();
                  categoryController.dispose();
                  unitController.dispose();
                  Navigator.of(ctx).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                ),
                child: const Text('创建'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showLogDialogForDate(ChoreItem choreItem, DateTime targetDate) {
    final memoController = TextEditingController();
    final valueController = TextEditingController();
    final members = context.read<ChoreProvider>().members;
    final List<Member> selectedMembers = [];

    final now = DateTime.now();
    DateTime selectedDateTime = (targetDate.year == now.year && targetDate.month == now.month && targetDate.day == now.day)
        ? now
        : DateTime(targetDate.year, targetDate.month, targetDate.day, now.hour, now.minute);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final dateStr = DateFormat('yyyy-MM-dd').format(targetDate);
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('$dateStr 打卡: ${choreItem.title}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('选择完成人员 (可多选):', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: members.map((m) {
                      final isSelected = selectedMembers.contains(m);
                      return FilterChip(
                        label: Text(m.name),
                        selected: isSelected,
                        selectedColor: Color(m.colorValue).withAlpha(76),
                        onSelected: (selected) {
                          setModalState(() {
                            if (selected) {
                              selectedMembers.add(m);
                            } else {
                              selectedMembers.remove(m);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  if (choreItem.isQuantifiable) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: valueController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: '输入量化数值 (${choreItem.unit})',
                        hintText: '例: 买菜花了 1200 元',
                        prefixIcon: const Icon(Icons.attach_money),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: memoController,
                    decoration: const InputDecoration(
                      labelText: '填写可选打卡备忘',
                      hintText: '例: 包含新鲜蔬菜与水果',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.access_time_filled, color: Color(0xFF10B981)),
                    title: Text(
                      '打卡时刻: ${DateFormat('yyyy-MM-dd HH:mm').format(selectedDateTime)}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    subtitle: const Text('支持精确到分钟的时间登记', style: TextStyle(fontSize: 11, color: Colors.white54)),
                    trailing: TextButton(
                      child: const Text('更改时刻'),
                      onPressed: () async {
                        final pickedDate = await showDatePicker(
                          context: ctx,
                          initialDate: selectedDateTime,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (pickedDate != null) {
                          if (!ctx.mounted) return;
                          final pickedTime = await showTimePicker(
                            context: ctx,
                            initialTime: TimeOfDay.fromDateTime(selectedDateTime),
                          );
                          if (pickedTime != null) {
                            setModalState(() {
                              selectedDateTime = DateTime(
                                pickedDate.year,
                                pickedDate.month,
                                pickedDate.day,
                                pickedTime.hour,
                                pickedTime.minute,
                              );
                            });
                          }
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  memoController.dispose();
                  valueController.dispose();
                  Navigator.of(ctx).pop();
                },
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (selectedMembers.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('请至少选择一名完成人员')),
                    );
                    return;
                  }

                  final double? numVal = choreItem.isQuantifiable
                      ? double.tryParse(valueController.text)
                      : null;

                  context.read<ChoreProvider>().logChore(
                        choreItem: choreItem,
                        selectedMembers: selectedMembers,
                        memo: memoController.text.trim(),
                        value: numVal,
                        targetDate: selectedDateTime,
                      );

                  memoController.dispose();
                  valueController.dispose();
                  Navigator.of(ctx).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                ),
                child: const Text('提交打卡'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final choreProvider = context.watch<ChoreProvider>();

    final now = DateTime.now();
    final recentDates = List.generate(5, (index) {
      return DateTime(now.year, now.month, now.day).subtract(Duration(days: index));
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('家务习惯打卡'),
        leading: IconButton(
          icon: const Icon(Icons.auto_awesome),
          tooltip: '智能助手',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AssistantScreen()),
            );
          },
        ),
        actions: [
          const SettingsButton(),
          IconButton(
            icon: const Icon(Icons.playlist_add_outlined),
            tooltip: '新建家务Item',
            onPressed: _showAddChoreDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
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
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // uHabits 标头栏
                  _buildGlassCard(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          const Expanded(
                            flex: 3,
                            child: Text('家务 / 习惯事项', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70, fontSize: 13)),
                          ),
                          Expanded(
                            flex: 5,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: recentDates.map((date) {
                                final isToday = date.day == now.day && date.month == now.month;
                                return Column(
                                  children: [
                                    Text(
                                      DateFormat('E').format(date),
                                      style: TextStyle(fontSize: 10, color: isToday ? const Color(0xFF818CF8) : Colors.white54),
                                    ),
                                    Text(
                                      '${date.day}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: isToday ? const Color(0xFF818CF8) : Colors.white,
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  choreProvider.choreItems.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Text('暂无家务事项，点击右上角【+】新建家务', style: TextStyle(color: Colors.grey, fontSize: 13)),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: choreProvider.choreItems.length,
                          itemBuilder: (context, index) {
                            final item = choreProvider.choreItems[index];

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12.0),
                              child: _buildGlassCard(
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(20),
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => ChoreDetailScreen(choreItem: item),
                                      ),
                                    );
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(14.0),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          flex: 3,
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Icon(
                                                    item.isQuantifiable ? Icons.monetization_on_outlined : Icons.check_circle_outline,
                                                    size: 18,
                                                    color: item.isQuantifiable ? const Color(0xFF34D399) : const Color(0xFF818CF8),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Flexible(
                                                    child: Text(
                                                      item.title,
                                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '${item.category} · ${item.isQuantifiable ? "量化(${item.unit})" : "打卡"}',
                                                style: const TextStyle(fontSize: 11, color: Colors.white54),
                                              ),
                                            ],
                                          ),
                                        ),

                                        // uHabits 矩阵 38x38dp 珍珠触控圈
                                        Expanded(
                                          flex: 5,
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                                            children: recentDates.map((date) {
                                              final logs = choreProvider.getLogsForChoreAndDate(item.id!, date);
                                              final isLogged = logs.isNotEmpty;
                                              final hasMemo = logs.any((l) => l.memo != null && l.memo!.isNotEmpty);

                                              final double totalValForDate = logs.fold(0.0, (sum, l) => sum + (l.value ?? 1.0));
                                              final formattedVal = NumberFormatter.formatQuantifiableValue(totalValForDate);

                                              return GestureDetector(
                                                onTap: () => _showLogDialogForDate(item, date),
                                                child: Stack(
                                                  clipBehavior: Clip.none,
                                                  children: [
                                                    AnimatedContainer(
                                                      duration: const Duration(milliseconds: 200),
                                                      width: 38,
                                                      height: 38,
                                                      decoration: BoxDecoration(
                                                        shape: BoxShape.circle,
                                                        color: isLogged
                                                            ? (item.isQuantifiable ? const Color(0xFF059669) : const Color(0xFF4F46E5))
                                                            : Colors.white.withAlpha(12),
                                                        boxShadow: isLogged
                                                            ? [
                                                                BoxShadow(
                                                                  color: (item.isQuantifiable ? const Color(0xFF10B981) : const Color(0xFF6366F1)).withAlpha(100),
                                                                  blurRadius: 8,
                                                                  spreadRadius: 1,
                                                                ),
                                                              ]
                                                            : [],
                                                        border: Border.all(
                                                          color: isLogged
                                                              ? Colors.transparent
                                                              : Colors.white.withAlpha(40),
                                                          width: 1,
                                                        ),
                                                      ),
                                                      child: Center(
                                                        child: isLogged
                                                            ? (item.isQuantifiable
                                                                ? Text(
                                                                    formattedVal,
                                                                    style: const TextStyle(
                                                                      fontSize: 10,
                                                                      fontWeight: FontWeight.bold,
                                                                      color: Colors.white,
                                                                    ),
                                                                  )
                                                                : const Icon(Icons.check, size: 20, color: Colors.white))
                                                            : Text(
                                                                '${date.day}',
                                                                style: const TextStyle(fontSize: 11, color: Colors.white60),
                                                              ),
                                                      ),
                                                    ),
                                                    if (isLogged && hasMemo)
                                                      Positioned(
                                                        top: -1,
                                                        right: -1,
                                                        child: Container(
                                                          width: 9,
                                                          height: 9,
                                                          decoration: BoxDecoration(
                                                            color: const Color(0xFFF59E0B),
                                                            shape: BoxShape.circle,
                                                            border: Border.all(color: const Color(0xFF0F172A), width: 1.5),
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                      ],
                                    ),
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
