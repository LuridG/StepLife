/// 数值智能缩写与格式化工具 (uHabits 风格: 1200 -> 1.2k, 1500000 -> 1.5M)
class NumberFormatter {
  static String formatQuantifiableValue(double value) {
    if (value == 0) return '0';

    final absVal = value.abs();
    final sign = value < 0 ? '-' : '';

    if (absVal < 1000) {
      // 小于 1000 显示精简数字
      if (absVal == absVal.toInt().toDouble()) {
        return '$sign${absVal.toInt()}';
      }
      return '$sign${absVal.toStringAsFixed(1)}';
    } else if (absVal < 1000000) {
      // 1000 ~ 999,999 缩写为 k
      final kVal = absVal / 1000.0;
      if (kVal >= 100 || kVal == kVal.toInt().toDouble()) {
        return '$sign${kVal.toInt()}k';
      }
      return '$sign${kVal.toStringAsFixed(1)}k';
    } else {
      // >= 1,000,000 缩写为 M
      final mVal = absVal / 1000000.0;
      if (mVal >= 100 || mVal == mVal.toInt().toDouble()) {
        return '$sign${mVal.toInt()}M';
      }
      return '$sign${mVal.toStringAsFixed(1)}M';
    }
  }
}
