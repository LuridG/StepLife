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
