import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/cache/cache_manager.dart';
import '../../../core/settings/settings_provider.dart';
import '../domain/life_templates.dart';

/// 按模板字段类型渲染动态表单控件（受控：value + onChanged）
///
/// 注意：文本类控件必须持有持久的 TextEditingController，
/// 否则每次 rebuild 重建控制器会导致输入时光标跳位/文字错乱。
class TemplateFieldWidget extends StatefulWidget {
  final TemplateField field;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  const TemplateFieldWidget({
    super.key,
    required this.field,
    required this.value,
    required this.onChanged,
  });

  @override
  State<TemplateFieldWidget> createState() => _TemplateFieldWidgetState();
}

class _TemplateFieldWidgetState extends State<TemplateFieldWidget> {
  late final TextEditingController _textController;
  late final TextEditingController _multiChoiceController;

  /// 标记本次重建是否由本组件自身输入触发（避免覆盖正在输入的内容）
  bool _selfChange = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: _textOf(widget.value));
    _multiChoiceController = TextEditingController();
  }

  @override
  void didUpdateWidget(covariant TemplateFieldWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selfChange) {
      // 自己输入引起的重建：保留用户正在输入的内容
      _selfChange = false;
      return;
    }
    final newText = _textOf(widget.value);
    if (newText != _textController.text) {
      _textController.text = newText;
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _multiChoiceController.dispose();
    super.dispose();
  }

  /// 把字段值转成文本框文本
  String _textOf(dynamic value) {
    if (widget.field.type == TemplateFieldType.tags) {
      final tags = (value is List) ? value.cast<String>() : <String>[];
      return tags.join('、');
    }
    if (widget.field.type == TemplateFieldType.number) {
      if (value is num) {
        final n = value.toDouble();
        return n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toString();
      }
      return '';
    }
    return value?.toString() ?? '';
  }

  /// 数字解析：仅当可解析时回传数字；不可解析（如输入 45. 中间态）不更新值，
  /// 避免 didUpdateWidget 用格式化后的文本覆盖用户输入。
  void _onNumberChanged(String v) {
    _selfChange = true;
    final parsed = double.tryParse(v.trim());
    if (parsed != null) {
      widget.onChanged(parsed);
    }
  }

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
      widget.onChanged(saved);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('图片保存失败: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  static const TextStyle _hintStyle = AppTheme.hintStyle;

  /// 多选列表：用户自定义新增选项（如自建 Jellyfin），自动加入选中值
  void _addCustomChoice() {
    final text = _multiChoiceController.text.trim();
    if (text.isEmpty) return;
    _multiChoiceController.clear();
    final current = (widget.value is List)
        ? List<String>.from(widget.value).where((e) => e.isNotEmpty).toList()
        : <String>[];
    final next = [...current];
    if (!next.contains(text)) next.add(text);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.field;
    final type = field.type;
    switch (type) {
      case TemplateFieldType.multiline:
        return TextField(
          controller: _textController,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: field.label,
            hintText: field.hint,
            hintStyle: _hintStyle,
          ),
          onChanged: (v) {
            _selfChange = true;
            widget.onChanged(v);
          },
        );
      case TemplateFieldType.number:
        return TextField(
          controller: _textController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: field.label,
            hintText: field.hint,
            hintStyle: _hintStyle,
          ),
          onChanged: _onNumberChanged,
        );
      case TemplateFieldType.rating:
        final rating = (widget.value is num) ? (widget.value as num).toDouble() : 5.0;
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
              onChanged: (v) => widget.onChanged(v),
            ),
          ],
        );
      case TemplateFieldType.choice:
        final options = field.options ?? const [];
        // 安全兜底：值不在选项中时回退到第一个选项，绝不因脏数据崩溃
        var current = widget.value?.toString() ??
            field.defaultValue ??
            (options.isNotEmpty ? options.first : '');
        if (options.isNotEmpty && !options.contains(current)) {
          current = options.first;
        }
        if (options.isEmpty) {
          return TextField(
            controller: _textController,
            decoration: InputDecoration(labelText: field.label, hintStyle: _hintStyle),
            onChanged: (v) {
              _selfChange = true;
              widget.onChanged(v);
            },
          );
        }
        return DropdownButtonFormField<String>(
          initialValue: current,
          decoration: InputDecoration(labelText: field.label),
          items: options
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: (v) {
            if (v != null) widget.onChanged(v);
          },
        );
      case TemplateFieldType.multiChoice:
        final selected = (widget.value is List)
            ? List<String>.from(widget.value).where((e) => e.isNotEmpty).toList()
            : ((widget.value?.toString().isNotEmpty ?? false)
                ? [widget.value!.toString()]
                : <String>[]);
        final baseOptions = (field.options ?? const []).toList();
        final hist = (field.suggestions ?? const [])
            .where((s) => s.isNotEmpty && !baseOptions.contains(s))
            .toList();
        final allOptions = [...baseOptions, ...hist];
        // 已选但不在候选中的值也展示，避免脏数据丢失
        for (final s in selected) {
          if (!allOptions.contains(s)) allOptions.add(s);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(field.label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            if (allOptions.isEmpty)
              const Text('暂无选项，可先在其他记录中填写', style: TextStyle(fontSize: 11, color: Colors.white38)),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: allOptions.map((o) {
                final isOn = selected.contains(o);
                return FilterChip(
                  label: Text(o, style: const TextStyle(fontSize: 12)),
                  selected: isOn,
                  selectedColor: const Color(0xFF10B981).withAlpha(90),
                  onSelected: (v) {
                    final next = [...selected];
                    if (v) {
                      if (!next.contains(o)) next.add(o);
                    } else {
                      next.remove(o);
                    }
                    widget.onChanged(next);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            // 自定义新增：允许用户自由添加平台/选项（如自建 Jellyfin）
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _multiChoiceController,
                    decoration: const InputDecoration(
                      hintText: '自定义新增，如: Jellyfin',
                      hintStyle: AppTheme.hintStyle,
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addCustomChoice(),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _addCustomChoice,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('添加'),
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFF10B981)),
                ),
              ],
            ),
          ],
        );

      case TemplateFieldType.date:
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_outlined, color: Color(0xFF10B981)),
          title: Text(
            widget.value?.toString() ?? '选择日期',
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
              widget.onChanged(picked.toIso8601String().substring(0, 10));
            }
          },
        );
      case TemplateFieldType.image:
        final path = widget.value?.toString();
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
                      onTap: () => widget.onChanged(''),
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
        final list = (widget.value is List) ? List<String>.from(widget.value) : <String>[];
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
                        widget.onChanged([...list, saved]);
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
                          onTap: () => widget.onChanged(list.where((x) => x != p).toList()),
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
          value: widget.value == true,
          onChanged: (v) => widget.onChanged(v),
        );
      case TemplateFieldType.tags:
        return TextField(
          controller: _textController,
          decoration: InputDecoration(
            labelText: field.label,
            hintText: '用、分隔多个标签',
            hintStyle: _hintStyle,
          ),
          onChanged: (v) {
            _selfChange = true;
            widget.onChanged(v.split('、').map((e) => e.trim()).where((e) => e.isNotEmpty).toList());
          },
        );
      case TemplateFieldType.text:
        return TextField(
          controller: _textController,
          decoration: InputDecoration(
            labelText: field.label,
            hintText: field.hint,
            hintStyle: _hintStyle,
          ),
          onChanged: (v) {
            _selfChange = true;
            widget.onChanged(v);
          },
        );
    }
  }
}
