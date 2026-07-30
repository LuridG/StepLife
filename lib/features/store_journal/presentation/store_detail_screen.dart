import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../domain/store_models.dart';
import '../providers/store_provider.dart';

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
                              child: Image.file(
                                File(storeItem.images[idx]),
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
                                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                                              onPressed: () => _confirmDeleteLog(context, log),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
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
