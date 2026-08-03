import 'dart:ui';
import 'package:flutter/material.dart';
import '../domain/life_templates.dart';

/// 模板画廊：选择要使用的模板后进入对应动态表单
class TemplateGallerySheet extends StatelessWidget {
  const TemplateGallerySheet({super.key});

  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const TemplateGallerySheet(),
    );
  }

  Widget _templateCard(BuildContext context, LifeTemplate tpl) {
    final icon = switch (tpl.iconName) {
      'movie' => Icons.movie_outlined,
      'restaurant' => Icons.restaurant_outlined,
      'menu_book' => Icons.menu_book_outlined,
      'landscape' => Icons.landscape_outlined,
      'shopping_bag' => Icons.shopping_bag_outlined,
      'snack' => Icons.fastfood_outlined,
      'basket' => Icons.shopping_basket_outlined,
      _ => Icons.dashboard_customize_outlined,
    };
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(tpl.key),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(14),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withAlpha(30), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: const Color(0xFF10B981), size: 28),
                const SizedBox(height: 8),
                Text(
                  tpl.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                ),
                const SizedBox(height: 3),
                Text(
                  tpl.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: Colors.white54),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.style_outlined, color: Color(0xFF10B981), size: 22),
                const SizedBox(width: 8),
                const Text(
                  '选择模板',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              '不同分类会记住各自绑定的模板，之后自动带出',
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.45,
                  children: LifeTemplates.all
                      .map((tpl) => _templateCard(context, tpl))
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
