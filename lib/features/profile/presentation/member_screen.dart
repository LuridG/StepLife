import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/settings/settings_button.dart';
import '../../chore_tracker/domain/chore_models.dart';
import '../../chore_tracker/providers/chore_provider.dart';
import '../../chore_tracker/presentation/member_dialog.dart';

class MemberScreen extends StatefulWidget {
  const MemberScreen({super.key});

  @override
  State<MemberScreen> createState() => _MemberScreenState();
}

class _MemberScreenState extends State<MemberScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('成员档案'),
        actions: [
          const SettingsButton(),
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            tooltip: '新增成员档案',
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => const MemberDialog(),
              );
            },
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
            Consumer<ChoreProvider>(
              builder: (context, provider, child) {
                final members = provider.members;

                if (members.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.badge_outlined, size: 48, color: Colors.white38),
                        const SizedBox(height: 12),
                        const Text('暂无成员档案记录', style: TextStyle(color: Colors.white70, fontSize: 14)),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (_) => const MemberDialog(),
                            );
                          },
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('新增成员档案'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('全员共 ${members.length} 人', style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                          TextButton.icon(
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (_) => const MemberDialog(),
                              );
                            },
                            icon: const Icon(Icons.person_add, size: 16, color: Color(0xFF10B981)),
                            label: const Text('新建成员', style: TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: members.length,
                        separatorBuilder: (ctx, index) => const SizedBox(height: 12),
                        itemBuilder: (ctx, index) {
                          final m = members[index];
                          return _buildGlassCard(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 20,
                                        backgroundColor: Color(m.colorValue),
                                        child: Text(
                                          m.name.isNotEmpty ? m.name[0] : '?',
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          m.name,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined, color: Color(0xFF38BDF8), size: 18),
                                        tooltip: '编辑成员',
                                        constraints: const BoxConstraints(),
                                        padding: const EdgeInsets.all(6),
                                        onPressed: () {
                                          showDialog(
                                            context: context,
                                            builder: (_) => MemberDialog(memberToEdit: m),
                                          );
                                        },
                                      ),
                                      const SizedBox(width: 4),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                                        tooltip: '删除成员',
                                        constraints: const BoxConstraints(),
                                        padding: const EdgeInsets.all(6),
                                        onPressed: () {
                                          _confirmDelete(context, provider, m);
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withAlpha(8),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.white12),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '性别: ${m.gender}   ·   身高: ${m.heightCm.toInt()} cm   ·   体重: ${m.weightKg.toInt()} kg',
                                          style: const TextStyle(fontSize: 12, color: Colors.white70, height: 1.4),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '出生日期: ${DateFormat('yyyy-MM-dd').format(m.birthDate)}  (动态计算 ${m.age} 岁)'
                                          '${m.customStrideCm != null ? '\n自定义步长: ${m.customStrideCm!.toInt()} cm' : ''}',
                                          style: const TextStyle(fontSize: 11.5, color: Colors.white60, height: 1.4),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, ChoreProvider provider, Member member) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('确认删除成员'),
        content: Text('确定要删除成员【${member.name}】的档案吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (member.id != null) {
                provider.deleteMember(member.id!);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('确定删除'),
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
