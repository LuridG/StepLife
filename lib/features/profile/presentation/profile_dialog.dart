import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/profile_provider.dart';

class ProfileDialog extends StatefulWidget {
  const ProfileDialog({super.key});

  @override
  State<ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<ProfileDialog> {
  late TextEditingController _heightController;
  late TextEditingController _weightController;
  late TextEditingController _ageController;
  late TextEditingController _strideController;
  late String _gender;

  @override
  void initState() {
    super.initState();
    final profile = context.read<ProfileProvider>().profile;
    _heightController = TextEditingController(text: profile.heightCm.toString());
    _weightController = TextEditingController(text: profile.weightKg.toString());
    _ageController = TextEditingController(text: profile.age.toString());
    _strideController = TextEditingController(
      text: profile.customStrideCm != null ? profile.customStrideCm.toString() : '',
    );
    _gender = profile.gender;
  }

  // 严格执行内存管理与销毁策略
  @override
  void dispose() {
    _heightController.dispose();
    _weightController.dispose();
    _ageController.dispose();
    _strideController.dispose();
    super.dispose();
  }

  void _save() {
    final height = double.tryParse(_heightController.text) ?? 170.0;
    final weight = double.tryParse(_weightController.text) ?? 65.0;
    final age = int.tryParse(_ageController.text) ?? 25;
    final customStride = double.tryParse(_strideController.text);

    context.read<ProfileProvider>().updateProfile(
          heightCm: height,
          weightKg: weight,
          gender: _gender,
          age: age,
          customStrideCm: customStride,
        );

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.person, color: Color(0xFF10B981)),
          SizedBox(width: 8),
          Text('个人身体参数设置'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
            TextField(
              controller: _heightController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '身高 (cm)',
                suffixText: 'cm',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _weightController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '体重 (kg)',
                suffixText: 'kg',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ageController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '年龄',
                suffixText: '岁',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _strideController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: '自定义步长 (可选)',
                hintText: '不填则依据身高自动推算',
                suffixText: 'cm',
              ),
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
          child: const Text('保存'),
        ),
      ],
    );
  }
}
