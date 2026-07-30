import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../domain/chore_models.dart';
import '../providers/chore_provider.dart';

class MemberDialog extends StatefulWidget {
  final Member? memberToEdit;

  const MemberDialog({super.key, this.memberToEdit});

  @override
  State<MemberDialog> createState() => _MemberDialogState();
}

class _MemberDialogState extends State<MemberDialog> {
  late TextEditingController _nameController;
  late TextEditingController _heightController;
  late TextEditingController _weightController;
  late TextEditingController _ageController;
  late TextEditingController _strideController;
  late String _gender;

  @override
  void initState() {
    super.initState();
    final m = widget.memberToEdit;
    _nameController = TextEditingController(text: m?.name ?? '');
    _heightController = TextEditingController(text: (m?.heightCm ?? 170.0).toString());
    _weightController = TextEditingController(text: (m?.weightKg ?? 65.0).toString());
    _ageController = TextEditingController(text: (m?.age ?? 25).toString());
    _strideController = TextEditingController(text: m?.customStrideCm != null ? m!.customStrideCm.toString() : '');
    _gender = m?.gender ?? '男';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _ageController.dispose();
    _strideController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入成员姓名/称呼')),
      );
      return;
    }

    final height = double.tryParse(_heightController.text) ?? 170.0;
    final weight = double.tryParse(_weightController.text) ?? 65.0;
    final age = int.tryParse(_ageController.text) ?? 25;
    final customStride = double.tryParse(_strideController.text);

    if (widget.memberToEdit == null) {
      context.read<ChoreProvider>().addMember(
            name: name,
            gender: _gender,
            heightCm: height,
            weightKg: weight,
            age: age,
            customStrideCm: customStride,
          );
    } else {
      final updated = widget.memberToEdit!.copyWith(
        name: name,
        gender: _gender,
        heightCm: height,
        weightKg: weight,
        age: age,
        customStrideCm: customStride,
      );
      context.read<ChoreProvider>().updateMember(updated);
    }

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.memberToEdit != null;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.person, color: Color(0xFF10B981)),
          const SizedBox(width: 8),
          Text(isEditing ? '编辑家庭成员档案' : '新增家庭成员档案'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '姓名/称呼 (如: 成员A/妈妈/小明)',
                prefixIcon: Icon(Icons.badge),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _gender,
              decoration: const InputDecoration(labelText: '性别'),
              items: const [
                DropdownMenuItem(value: '男', child: Text('男')),
                DropdownMenuItem(value: '女', child: Text('女')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _gender = val);
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _heightController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: '身高 (cm)',
                      suffixText: 'cm',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _weightController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: '体重 (kg)',
                      suffixText: 'kg',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ageController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '年龄',
                      suffixText: '岁',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _strideController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: '自定义步长(可选)',
                      suffixText: 'cm',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: Colors.white,
          ),
          child: const Text('保存档案'),
        ),
      ],
    );
  }
}
