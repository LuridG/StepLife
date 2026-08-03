import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// 拉起地图应用定位到指定地点（高德 / 百度 / 腾讯 / 系统地图）
/// 优先尝试已安装的地图 App，全部不可用则给出提示。
Future<void> launchMapForPlace(BuildContext context, String address) async {
  final query = Uri.encodeComponent(address);
  final targets = <(String, String)>[
    ('高德地图', 'androidamap://search/query?query=$query'),
    ('百度地图', 'baidumap://map/place/search?query=$query'),
    ('腾讯地图', 'qqmap://map/geocoder?addr=$query'),
    ('系统地图', 'geo:0,0?q=$query'),
  ];

  if (!context.mounted) return;
  final picked = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: const Color(0xFF0F172A),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              '用地图打开位置',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          ...targets.map(
            (t) => ListTile(
              leading: const Icon(Icons.map_outlined, color: Color(0xFF10B981)),
              title: Text(t.$1, style: const TextStyle(fontSize: 14, color: Colors.white)),
              onTap: () => Navigator.of(sheetCtx).pop(t.$2),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (picked == null) return;

  final uri = Uri.parse(picked);
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    opened = false;
  }
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('未能打开地图应用，请检查是否已安装对应地图')),
    );
  }
}
