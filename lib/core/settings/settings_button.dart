import 'package:flutter/material.dart';
import 'settings_screen.dart';

/// 全局设置入口：右上角齿轮按钮（注入各 Tab AppBar）
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.settings_outlined),
      tooltip: '设置中心',
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );
      },
    );
  }
}
