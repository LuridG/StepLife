import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

/// 获取当前定位并自动返回可填写的位置描述：
/// 优先逆地理编码为可读地址（Nominatim 免费服务），失败时回退为「纬度,经度」坐标。
/// 返回 null 表示定位服务/权限不可用或定位失败。
Future<String?> pickCurrentLocation() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 15),
      ),
    );
    final address = await _reverseGeocode(pos.latitude, pos.longitude);
    if (address != null && address.isNotEmpty) return address;
    return '${pos.latitude.toStringAsFixed(6)},${pos.longitude.toStringAsFixed(6)}';
  } catch (_) {
    return null;
  }
}

Future<String?> _reverseGeocode(double lat, double lng) async {
  try {
    final uri = Uri.parse(
      'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=$lat&lon=$lng&accept-language=zh-CN',
    );
    final resp = await http
        .get(uri, headers: {'User-Agent': 'StepLife/1.0'})
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      if (data is Map && data['display_name'] != null) {
        return data['display_name'].toString();
      }
    }
  } catch (_) {}
  return null;
}
