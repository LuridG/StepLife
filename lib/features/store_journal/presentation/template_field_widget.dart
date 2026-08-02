import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../../core/cache/cache_manager.dart';
import '../../../core/settings/settings_provider.dart';
import '../domain/life_templates.dart';

/// 按模板字段类型渲染动态表单控件（受控：value + onChanged）
class TemplateFieldWidget extends StatelessWidget {
  final TemplateField field;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  const TemplateFieldWidget({
    super.key,
    required this.field,
    required this.value,
    required this.onChanged,
  });

  Future<void> _pickImage(BuildContext context, {required bool tmdb}) async {
    final picker = ImagePicker();
    final quality = context.read<SettingsProvider>().imageQuality;
    final XFile? img = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: quality,
    );
    if (img == null) return;
    try {
      final saved = await CacheManager.instance.copyToCache(img.path, tmdb: tmdb);
      onChanged(saved);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('图片保存失败: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = field.type;
    switch (type) {
      case TemplateFieldType.multiline:
        return TextField(
          controller: TextEditingController(text: value?.toString() ?? ''),
          maxLines: 3,
          decoration: InputDecoration(labelText: field.label, hintText: field.hint),
          onChanged: onChanged,
        );
      case TemplateFieldType.number:
        return TextField(
          controller: TextEditingController(text: value?.toString() ?? ''),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: field.label, hintText: field.hint),
          onChanged: (v) => onChanged(double.tryParse(v)),
        );
      case TemplateFieldType.rating:
        final rating = (value is num) ? (value as num).toDouble() : 5.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(field.label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text('⭐ ${rating.toStringAsFixed(1)} 分', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
            Slider(
              value: rating,
              min: 1.0,
              max: 5.0,
              divisions: 8,
              activeColor: Colors.amber,
              inactiveColor: Colors.amber.withAlpha(50),
              label: '${rating.toStringAsFixed(1)}分',
              onChanged: (v) => onChanged(v),
            ),
          ],
        );
      case TemplateFieldType.choice:
        final options = field.options ?? const [];
        // 安全兜底：值不在选项中时回退到第一个选项，绝不因脏数据崩溃
        var current = value?.toString() ?? field.defaultValue ?? (options.isNotEmpty ? options.first : '');
        if (options.isNotEmpty && !options.contains(current)) {
          current = options.first;
        }
        if (options.isEmpty) {
          return TextField(
            controller: TextEditingController(text: current),
            decoration: InputDecoration(labelText: field.label),
            onChanged: onChanged,
          );
        }
        return DropdownButtonFormField<String>(
          initialValue: current,
          decoration: InputDecoration(labelText: field.label),
          items: options
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        );
      case TemplateFieldType.date:
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_outlined, color: Color(0xFF10B981)),
          title: Text(
            value?.toString() ?? '选择日期',
            style: const TextStyle(fontSize: 14),
          ),
          subtitle: Text(field.label, style: const TextStyle(fontSize: 12, color: Colors.white54)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2035),
            );
            if (picked != null) {
              onChanged(picked.toIso8601String().substring(0, 10));
            }
          },
        );
      case TemplateFieldType.image:
        final path = value?.toString();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(field.label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            if (path != null && path.isNotEmpty)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(File(path), width: 70, height: 70, fit: BoxFit.cover,
                      errorBuilder: (c, e, s) => Container(width: 70, height: 70, color: Colors.white10, child: const Icon(Icons.broken_image, color: Colors.grey)),
                    ),
                  ),
                  Positioned(
                    top: 2, right: 2,
                    child: GestureDetector(
                      onTap: () => onChanged(''),
                      child: Container(
                        decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
                        child: const Icon(Icons.close, color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                ],
              )
            else
              TextButton.icon(
                onPressed: () => _pickImage(context, tmdb: false),
                icon: const Icon(Icons.add_a_photo, size: 16),
                label: const Text('添加图片'),
                style: TextButton.styleFrom(foregroundColor: const Color(0xFF10B981)),
              ),
          ],
        );
      case TemplateFieldType.images:
        final list = (value is List) ? List<String>.from(value) : <String>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${field.label}（已选 ${list.length}/3 张）', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                if (list.length < 3)
                  TextButton.icon(
                    onPressed: () async {
                      final picker = ImagePicker();
                      final quality = context.read<SettingsProvider>().imageQuality;
                      final XFile? img = await picker.pickImage(source: ImageSource.gallery, imageQuality: quality);
                      if (img == null) return;
                      try {
                        final saved = await CacheManager.instance.copyToCache(img.path);
                        onChanged([...list, saved]);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('图片保存失败: $e'), backgroundColor: Colors.redAccent),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.add_a_photo, size: 16),
                    label: const Text('添加照片'),
                    style: TextButton.styleFrom(foregroundColor: const Color(0xFF10B981)),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (list.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: list.map((p) {
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(File(p), width: 70, height: 70, fit: BoxFit.cover,
                          errorBuilder: (c, e, s) => Container(width: 70, height: 70, color: Colors.white10, child: const Icon(Icons.broken_image, color: Colors.grey)),
                        ),
                      ),
                      Positioned(
                        top: 2, right: 2,
                        child: GestureDetector(
                          onTap: () => onChanged(list.where((x) => x != p).toList()),
                          child: Container(
                            decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
                            child: const Icon(Icons.close, color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
          ],
        );
      case TemplateFieldType.switchField:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(field.label, style: const TextStyle(fontSize: 14)),
          value: value == true,
          onChanged: (v) => onChanged(v),
        );
      case TemplateFieldType.tags:
        final tags = (value is List) ? (value).cast<String>() : <String>[];
        return TextField(
          controller: TextEditingController(text: tags.join('、')),
          decoration: InputDecoration(labelText: field.label, hintText: '用、分隔多个标签'),
          onChanged: (v) => onChanged(v.split('、').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()),
        );
      case TemplateFieldType.text:
        return TextField(
          controller: TextEditingController(text: value?.toString() ?? ''),
          decoration: InputDecoration(labelText: field.label, hintText: field.hint),
          onChanged: onChanged,
        );
    }
  }
}
