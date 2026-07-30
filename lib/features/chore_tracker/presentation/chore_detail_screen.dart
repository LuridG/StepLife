import 'package:flutter/material.dart';
import 'package:flutter_heatmap_calendar/flutter_heatmap_calendar.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../domain/chore_models.dart';
import '../providers/chore_provider.dart';

class ChoreDetailScreen extends StatelessWidget {
  final ChoreItem choreItem;

  const ChoreDetailScreen({super.key, required this.choreItem});

  @override
  Widget build(BuildContext context) {
    final choreProvider = context.watch<ChoreProvider>();
    final logs = choreProvider.choreLogs.where((l) => l.choreId == choreItem.id).toList();
    final heatmapData = choreProvider.getHeatmapDatasetsForChore(choreItem.id!);
    final memberStats = choreProvider.getMemberContributionStats(choreItem.id!);

    final double totalValue = logs.fold(0.0, (sum, l) => sum + (l.value ?? 1.0));

    return Scaffold(
      appBar: AppBar(
        title: Text('${choreItem.title} - 任务详情与统计'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 概览信息卡片
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4338CA), Color(0xFF6366F1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '分类: ${choreItem.category}',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            choreItem.isQuantifiable ? '量化登记 (${choreItem.unit})' : '完成打卡',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white30, height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatItem('累计打卡', '${logs.length} 次'),
                        if (choreItem.isQuantifiable)
                          _buildStatItem('累计数值', '${totalValue.toStringAsFixed(1)} ${choreItem.unit}'),
                        _buildStatItem('参与人数', '${memberStats.length} 人'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 该任务专属热力图 (Dedicated Calendar Heatmap)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.grid_on, color: Color(0xFF6366F1)),
                        SizedBox(width: 8),
                        Text('专属历史打卡热力图', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    HeatMap(
                      datasets: heatmapData,
                      colorMode: ColorMode.color,
                      showColorTip: true,
                      showText: false,
                      scrollable: true,
                      size: 24,
                      colorsets: const {
                        1: Color(0xFFC7D2FE),
                        2: Color(0xFF818CF8),
                        3: Color(0xFF6366F1),
                        5: Color(0xFF4338CA),
                      },
                      onClick: (value) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('${DateFormat('yyyy-MM-dd').format(value)} 打卡 ${heatmapData[value] ?? 0} 次')),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 量化/参与度统计图表 (Quantifiable Distribution Pie Chart)
            if (memberStats.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.pie_chart, color: Color(0xFF10B981)),
                          const SizedBox(width: 8),
                          Text(
                            choreItem.isQuantifiable ? '成员量化贡献/消费占比' : '成员完成次数分布',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 180,
                        child: PieChart(
                          PieChartData(
                            sectionsSpace: 2,
                            centerSpaceRadius: 40,
                            sections: memberStats.entries.map((e) {
                              final textDisplay = choreItem.isQuantifiable
                                  ? '${e.key}\n${e.value.toStringAsFixed(1)}${choreItem.unit}'
                                  : '${e.key}\n${e.value.toInt()}次';
                              return PieChartSectionData(
                                title: textDisplay,
                                value: e.value,
                                radius: 50,
                                titleStyle: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 20),

            // 详细打卡记录流水
            const Text('历史打卡日志记录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            logs.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Center(child: Text('暂无历史打卡记录', style: TextStyle(color: Colors.grey))),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final log = logs[index];
                      final timeStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(log.timestamp);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFF6366F1),
                            child: Icon(Icons.task_alt, color: Colors.white),
                          ),
                          title: Text('人员: ${log.memberNames.join(', ')}',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (choreItem.isQuantifiable && log.value != null)
                                Text(
                                  '数值/花费: ${log.value!.toStringAsFixed(1)} ${choreItem.unit}',
                                  style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold),
                                ),
                              if (log.memo != null && log.memo!.isNotEmpty)
                                Text('备忘: ${log.memo}', style: const TextStyle(color: Colors.white70, fontStyle: FontStyle.italic)),
                              Text('时间: $timeStr', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                            onPressed: () => choreProvider.deleteLog(log.id!),
                          ),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    );
  }
}
