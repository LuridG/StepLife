import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
      ),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
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
                // App 图标呈现 (无白边透明版本)
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withAlpha(60),
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
                  'StepLife - 步履家务',
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
                  child: const Text(
                    '版本号: v1.0.0 (Build 1)',
                    style: TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '结合路线步量换算与家务习惯登记的移动/桌面应用',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 24),

                // 更新历史与版本日志
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
                          version: 'v1.0.0 (2026-07-30)',
                          isLatest: true,
                          changes: [
                            '🏃 步量客观路线资产拆分：路线属性与履约打卡解耦，纵向列表依序展示，支持锁定与编辑。',
                            '🏠 uHabits 打卡风格：家务打卡支持日期矩阵，量化家务支持 1.2k/15k 智能缩写。',
                            '👥 统一家庭成员系统：整合身高、体重、性别档案，按个人体貌精密推算距离与 MET 千卡。',
                            '💻 Windows 原生适配：集成 SQLite FFI 桌面驱动与无白边透明 ICO 图标。',
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // 架构与文档查看
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
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withAlpha(30), width: 1),
          ),
          child: child,
        ),
      ),
    );
  }
}
