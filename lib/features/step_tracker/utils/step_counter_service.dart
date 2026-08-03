import 'dart:async';
import 'dart:io';
import 'package:pedometer/pedometer.dart';

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

  /// 开始监听系统计步器累计值（Android）；非 Android 返回 false
  static Future<bool> start() async {
    if (!isSupported) return false;
    try {
      await stop();
      _stream = Pedometer.stepCountStream.map((sc) => sc.steps);
      _sub = _stream?.listen((n) => _lastSteps = n);
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
}
