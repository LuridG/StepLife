import 'dart:async';
import 'dart:io';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

/// 系统计步器封装：Android 通过 step counter 传感器读取累计步数差值，
/// 其他平台（Windows 桌面等）无传感器，返回不支持。
class StepCounterService {
  static Stream<int>? _stream;
  static StreamSubscription<int>? _sub;
  static int _lastSteps = 0;
  static bool _listening = false;

  /// 是否支持系统计步（仅 Android）
  static bool get isSupported => Platform.isAndroid;

  /// 是否正在监听计步器
  static bool get isListening => _listening;

  /// 当前累计步数（开始监听后实时更新）
  static int get currentSteps => _lastSteps;

  /// 开始监听系统计步器累计值（Android）；非 Android 返回 false。
  /// Android 10+ 会先请求 ACTIVITY_RECOGNITION 权限，拒绝则返回 false。
  static Future<bool> start() async {
    if (!isSupported) return false;
    try {
      if (!await _ensurePermission()) return false;
      await stop();
      _stream = Pedometer.stepCountStream.map((sc) => sc.steps);
      _sub = _stream?.listen(
        (n) => _lastSteps = n,
        onError: (Object _) {
          // 传感器不可用/权限被收回等异常：停止监听，避免流静默失效
          _listening = false;
          _sub?.cancel();
          _sub = null;
          _stream = null;
        },
      );
      _listening = true;
      return true;
    } catch (_) {
      _listening = false;
      return false;
    }
  }

  /// 停止监听（测量结束后释放）
  static Future<void> stop() async {
    try {
      await _sub?.cancel();
    } catch (_) {}
    _sub = null;
    _stream = null;
    _listening = false;
  }

  /// Android 10+ 需要运行时授权身体活动识别权限
  static Future<bool> _ensurePermission() async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.activityRecognition.status;
    if (status.isGranted) return true;
    final result = await Permission.activityRecognition.request();
    return result.isGranted;
  }
}
