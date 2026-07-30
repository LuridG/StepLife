import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../domain/chore_models.dart';
import '../providers/chore_provider.dart';
import 'member_dialog.dart';

class MemberManagementDialog extends StatelessWidget {
  const MemberManagementDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ChoreProvider>(
      builder: (context, provider, child) {
        final members = provider.members;

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.badge, color: Color(0xFF10B981)),
                  SizedBox(width: 8),
                  Text('成员档案整理', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => const MemberDialog(),
                  );
                },
                icon: const Icon(Icons.person_add, size: 16),
                label: const Text('新增', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: members.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('暂无成员档案，点击右上角【+ 新增】添加。', style: TextStyle(color: Colors.white54, fontSize: 13)),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: members.length,
                    separatorBuilder: (ctx, index) => const Divider(height: 1, color: Colors.white12),
                    itemBuilder: (ctx, index) {
                      final m = members[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                        leading: CircleAvatar(
                          backgroundColor: Color(m.colorValue),
                          child: Text(
                            m.name.isNotEmpty ? m.name[0] : '?',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(
                          m.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                        ),
                        subtitle: Text(
                          '${m.gender} · ${m.heightCm.toInt()}cm/${m.weightKg.toInt()}kg · ${DateFormat('yyyy-MM').format(m.birthDate)}生(${m.age}岁)'
                          '${m.customStrideCm != null ? ' · 步长${m.customStrideCm!.toInt()}cm' : ''}',
                          style: const TextStyle(fontSize: 11, color: Colors.white60),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, color: Color(0xFF38BDF8), size: 20),
                              tooltip: '编辑',
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (_) => MemberDialog(memberToEdit: m),
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                              tooltip: '删除',
                              onPressed: () {
                                _confirmDelete(context, provider, m);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
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
}
