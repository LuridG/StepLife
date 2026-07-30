import 'dart:math';

/// 健身计算工具类 (Fitness Calculator)
/// 提供步长推算、距离转换、步频估算与 MET 卡路里消耗计算算法
class FitnessCalculator {
  /// 根据身高估计标准步长 (单位: cm)
  /// 女性一般系数约为 0.413, 男性约为 0.415
  static double estimateStrideLength({
    required double heightCm,
    required String gender,
  }) {
    if (heightCm <= 0) return 65.0; // 默认值
    final factor = (gender.toLowerCase() == 'female' || gender == '女') ? 0.413 : 0.415;
    return heightCm * factor;
  }

  /// 步数转公里数 (Kilometers)
  /// [steps]: 走的总步数
  /// [strideLengthCm]: 步长 (厘米)
  static double stepsToKilometers(int steps, double strideLengthCm) {
    if (steps <= 0 || strideLengthCm <= 0) return 0.0;
    // 1 km = 100,000 cm
    return (steps * strideLengthCm) / 100000.0;
  }

  /// 根据步数与运动时长(分钟)计算步频 (Cadence: 步/分钟)
  static double calculateCadence(int steps, int durationMinutes) {
    if (steps <= 0 || durationMinutes <= 0) return 0.0;
    return steps / durationMinutes;
  }

  /// 根据步频估计 MET (Metabolic Equivalent of Task) 强度值
  /// 慢速 (<80步/分): MET=2.8
  /// 中速 (80~110步/分): MET=3.5
  /// 快速 (110~130步/分): MET=4.5
  /// 极快 (>130步/分): MET=6.0
  static double getMetByCadence(double cadence) {
    if (cadence <= 0) return 3.0; // 默认中速走
    if (cadence < 80) {
      return 2.8;
    } else if (cadence <= 110) {
      return 3.5;
    } else if (cadence <= 130) {
      return 4.5;
    } else {
      return 6.0;
    }
  }

  /// 计算消耗的千卡热量 (Calories Burned in kcal)
  /// 公式: Calories (kcal) = MET * 体重(kg) * 运动时长(小时)
  /// [steps]: 步数
  /// [durationMinutes]: 运动时长 (分钟)
  /// [weightKg]: 体重 (公斤)
  /// [cadenceOverride]: 可选直接传入已知步频
  static double calculateCalories({
    required int steps,
    required int durationMinutes,
    required double weightKg,
    double? cadenceOverride,
  }) {
    if (steps <= 0 || weightKg <= 0) return 0.0;

    final duration = durationMinutes > 0 ? durationMinutes : 30; // 缺省按照30分钟推算
    final cadence = cadenceOverride ?? calculateCadence(steps, duration);
    final met = getMetByCadence(cadence);

    final durationHours = duration / 60.0;
    final calories = met * weightKg * durationHours;

    return max(0.0, calories);
  }
}
