import '../domain/store_models.dart';

/// 菜篮子价格统计：从打卡记录(StoreLog)提取单价序列，计算涨跌/均线/月度聚合。
/// 单价取自打卡 extras['price']（元/单位），打卡时间取 log.timestamp。
/// 品牌取自 extras['brand']（可空，视为「通用」），所有统计支持按品牌过滤。
class BasketStats {
  /// 打卡记录所属品牌（extras['brand'] 去空格，空视为空串）
  static String brandOf(StoreLog log) =>
      (log.extras['brand']?.toString() ?? '').trim();

  /// 品牌显示名：无品牌记录显示「通用」
  static String brandLabel(StoreLog log) {
    final b = brandOf(log);
    return b.isEmpty ? '通用' : b;
  }

  /// 该商品出现过的品牌列表（通用排最前，其余按首次出现顺序）
  static List<String> brandsOf(List<StoreLog> logs) {
    final result = <String>[];
    for (final l in logs) {
      final b = brandLabel(l);
      if (!result.contains(b)) result.add(b);
    }
    result.sort((a, b) {
      if (a == '通用') return -1;
      if (b == '通用') return 1;
      return a.compareTo(b);
    });
    return result;
  }

  static List<StoreLog> _filtered(List<StoreLog> logs, String? brand) {
    if (brand == null || brand.isEmpty || brand == '全部') return logs;
    return logs.where((l) => brandLabel(l) == brand).toList();
  }

  /// 按时间升序的单价序列（过滤无效价格）
  static List<double> priceSeries(List<StoreLog> logs, {String? brand}) {
    logs = _filtered(logs, brand);
    final sorted = [...logs]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return sorted
        .map((l) => (l.extras['price'] as num?)?.toDouble() ?? 0)
        .where((p) => p > 0)
        .toList();
  }

  /// 按时间升序的价格记录（log + price），供图表使用
  static List<({StoreLog log, double price})> pricePoints(
      List<StoreLog> logs,
      {String? brand}) {
    logs = _filtered(logs, brand);
    final sorted = [...logs]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final points = <({StoreLog log, double price})>[];
    for (final l in sorted) {
      final p = (l.extras['price'] as num?)?.toDouble() ?? 0;
      if (p > 0) points.add((log: l, price: p));
    }
    return points;
  }

  /// 最近单价（无记录返回 null）
  static double? latestPrice(List<StoreLog> logs, {String? brand}) {
    final s = priceSeries(logs, brand: brand);
    return s.isEmpty ? null : s.last;
  }

  /// 最近一次价格记录时间
  static DateTime? latestTime(List<StoreLog> logs, {String? brand}) {
    final pts = pricePoints(logs, brand: brand);
    return pts.isEmpty ? null : pts.last.log.timestamp;
  }

  /// 较上次涨跌幅（比例，如 0.08 = 涨 8%）；无法计算返回 null
  static double? changeVsPrevious(List<StoreLog> logs, {String? brand}) {
    final s = priceSeries(logs, brand: brand);
    if (s.length < 2) return null;
    final prev = s[s.length - 2];
    if (prev <= 0) return null;
    return (s.last - prev) / prev;
  }

  /// 较 N 天前的涨跌幅：取 N 天前最后一条记录作为基准
  static double? changeVsDaysAgo(List<StoreLog> logs, int days,
      {String? brand}) {
    final pts = pricePoints(logs, brand: brand);
    if (pts.isEmpty) return null;
    final cutoff = DateTime.now().subtract(Duration(days: days));
    double? base;
    for (final pt in pts) {
      if (pt.log.timestamp.isBefore(cutoff)) base = pt.price;
    }
    final latest = pts.last.price;
    if (base == null || base <= 0) return null;
    return (latest - base) / base;
  }

  /// 近 N 天均价
  static double? avgPriceSince(List<StoreLog> logs, int days,
      {String? brand}) {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final prices = _filtered(logs, brand)
        .where((l) => !l.timestamp.isBefore(cutoff))
        .map((l) => (l.extras['price'] as num?)?.toDouble() ?? 0)
        .where((p) => p > 0)
        .toList();
    if (prices.isEmpty) return null;
    return prices.reduce((a, b) => a + b) / prices.length;
  }

  /// 较上月涨跌幅：上月最后一条 vs 本月最新
  static double? changeVsLastMonth(List<StoreLog> logs, {String? brand}) {
    final pts = pricePoints(logs, brand: brand);
    if (pts.length < 2) return null;
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month);
    double? lastMonthPrice;
    for (final pt in pts) {
      if (pt.log.timestamp.isBefore(thisMonth)) lastMonthPrice = pt.price;
    }
    final latest = pts.last.price;
    if (lastMonthPrice == null || lastMonthPrice <= 0) return null;
    return (latest - lastMonthPrice) / lastMonthPrice;
  }

  /// 7 日移动平均（按记录时刻线性平滑，输出与价格点等长）
  static List<double> movingAverage(List<StoreLog> logs,
      {int windowDays = 7, String? brand}) {
    final pts = pricePoints(logs, brand: brand);
    if (pts.isEmpty) return const [];
    final out = <double>[];
    for (var i = 0; i < pts.length; i++) {
      final windowStart = pts[i].log.timestamp.subtract(Duration(days: windowDays));
      double sum = 0;
      var cnt = 0;
      for (var j = 0; j <= i; j++) {
        if (!pts[j].log.timestamp.isBefore(windowStart)) {
          sum += pts[j].price;
          cnt++;
        }
      }
      out.add(cnt > 0 ? sum / cnt : pts[i].price);
    }
    return out;
  }

  /// 按自然月聚合均价: Map<'yyyy-MM', double>
  static Map<String, double> monthlyAverage(List<StoreLog> logs,
      {String? brand}) {
    final map = <String, List<double>>{};
    for (final l in _filtered(logs, brand)) {
      final p = (l.extras['price'] as num?)?.toDouble() ?? 0;
      if (p <= 0) continue;
      final key =
          '${l.timestamp.year}-${l.timestamp.month.toString().padLeft(2, '0')}';
      map.putIfAbsent(key, () => []).add(p);
    }
    final result = <String, double>{};
    map.forEach((k, v) {
      result[k] = v.reduce((a, b) => a + b) / v.length;
    });
    return result;
  }

  /// 涨跌方向: 'up' / 'down' / 'flat'；无对比基准返回 null
  static String? trendDirection(List<StoreLog> logs,
      {double threshold = 0.005, String? brand}) {
    final c = changeVsPrevious(logs, brand: brand);
    if (c == null) return null;
    if (c > threshold) return 'up';
    if (c < -threshold) return 'down';
    return 'flat';
  }

  /// 涨跌幅格式化：0.08 -> '+8%'，-0.05 -> '-5%'，0 -> '0%'
  static String formatPct(double? ratio) {
    if (ratio == null) return '—';
    final pct = ratio * 100;
    final sign = pct > 0 ? '+' : '';
    final abs = pct.abs();
    final text = abs >= 10 ? abs.toStringAsFixed(0) : abs.toStringAsFixed(1);
    return '$sign$text%';
  }
}
