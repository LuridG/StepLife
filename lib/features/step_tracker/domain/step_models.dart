class RouteItem {
  final int? id;
  final String name;
  final String? description;
  final String measuredBy;
  final int refSteps;
  final bool isLocked;
  final DateTime createdAt;

  RouteItem({
    this.id,
    required this.name,
    this.description,
    this.measuredBy = '自己',
    this.refSteps = 2000,
    this.isLocked = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  RouteItem copyWith({
    int? id,
    String? name,
    String? description,
    String? measuredBy,
    int? refSteps,
    bool? isLocked,
    DateTime? createdAt,
  }) {
    return RouteItem(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      measuredBy: measuredBy ?? this.measuredBy,
      refSteps: refSteps ?? this.refSteps,
      isLocked: isLocked ?? this.isLocked,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'measuredBy': measuredBy,
      'refSteps': refSteps,
      'isLocked': isLocked ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory RouteItem.fromMap(Map<String, dynamic> map) {
    return RouteItem(
      id: map['id'] as int?,
      name: map['name'] as String,
      description: map['description'] as String?,
      measuredBy: map['measuredBy'] as String? ?? '自己',
      refSteps: map['refSteps'] as int? ?? 2000,
      isLocked: (map['isLocked'] as int? ?? 0) == 1,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }
}

class StepLog {
  final int? id;
  final int? routeId;
  final String routeName;
  final String walkerName;
  final int timesCount;
  final int steps;
  final int durationMinutes;
  final double distanceKm;
  final double caloriesKcal;
  final DateTime timestamp;

  StepLog({
    this.id,
    this.routeId,
    required this.routeName,
    this.walkerName = '自己',
    this.timesCount = 1,
    required this.steps,
    required this.durationMinutes,
    required this.distanceKm,
    required this.caloriesKcal,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'routeId': routeId,
      'routeName': routeName,
      'walkerName': walkerName,
      'timesCount': timesCount,
      'steps': steps,
      'durationMinutes': durationMinutes,
      'distanceKm': distanceKm,
      'caloriesKcal': caloriesKcal,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory StepLog.fromMap(Map<String, dynamic> map) {
    return StepLog(
      id: map['id'] as int?,
      routeId: map['routeId'] as int?,
      routeName: map['routeName'] as String,
      walkerName: map['walkerName'] as String? ?? '自己',
      timesCount: map['timesCount'] as int? ?? 1,
      steps: map['steps'] as int,
      durationMinutes: map['durationMinutes'] as int,
      distanceKm: (map['distanceKm'] as num).toDouble(),
      caloriesKcal: (map['caloriesKcal'] as num).toDouble(),
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}

/// 路线单程步数测量记录：一次测量 = 实际总步数 ÷ 倍数（如往返 2 倍）
class RouteMeasurement {
  final int? id;
  final int routeId;
  final int steps; // 本次实际走的总步数
  final double multiplier; // 倍数（支持一位小数，如 1.5 / 2.0 / 1.8）
  final int computedSteps; // 单程步数 = round(steps / multiplier)
  final String measuredBy;
  final DateTime createdAt;

  RouteMeasurement({
    this.id,
    required this.routeId,
    required this.steps,
    required this.multiplier,
    required this.computedSteps,
    this.measuredBy = '自己',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 由实际总步数与倍数计算单程步数（四舍五入）
  static int computeSingleSteps(int steps, double multiplier) {
    if (multiplier <= 0) return steps;
    return (steps / multiplier).round();
  }

  RouteMeasurement copyWith({
    int? id,
    int? routeId,
    int? steps,
    double? multiplier,
    int? computedSteps,
    String? measuredBy,
    DateTime? createdAt,
  }) {
    return RouteMeasurement(
      id: id ?? this.id,
      routeId: routeId ?? this.routeId,
      steps: steps ?? this.steps,
      multiplier: multiplier ?? this.multiplier,
      computedSteps: computedSteps ?? this.computedSteps,
      measuredBy: measuredBy ?? this.measuredBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'routeId': routeId,
      'steps': steps,
      'multiplier': multiplier,
      'computedSteps': computedSteps,
      'measuredBy': measuredBy,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory RouteMeasurement.fromMap(Map<String, dynamic> map) {
    return RouteMeasurement(
      id: map['id'] as int?,
      routeId: map['routeId'] as int,
      steps: map['steps'] as int,
      multiplier: (map['multiplier'] as num).toDouble(),
      computedSteps: map['computedSteps'] as int,
      measuredBy: map['measuredBy'] as String? ?? '自己',
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }
}
