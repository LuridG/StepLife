import 'package:flutter/foundation.dart';
import '../domain/step_models.dart';
import '../../profile/domain/user_profile.dart';
import '../../chore_tracker/domain/chore_models.dart';
import '../../../core/db/database_service.dart';
import '../../../core/utils/fitness_calculator.dart';

class StepProvider extends ChangeNotifier {
  List<RouteItem> _routes = [];
  List<StepLog> _stepLogs = [];
  List<RouteMeasurement> _measurements = [];
  bool _isLoading = true;

  List<RouteItem> get routes => _routes;
  List<StepLog> get stepLogs => _stepLogs;
  List<RouteMeasurement> get measurements => _measurements;
  bool get isLoading => _isLoading;

  /// 某路线的测量记录（按时间倒序）
  List<RouteMeasurement> measurementsOf(int routeId) =>
      _measurements.where((m) => m.routeId == routeId).toList();

  /// 某路线测量次数
  int measurementCountOf(int routeId) => measurementsOf(routeId).length;

  StepProvider() {
    loadData();
  }

  Future<void> loadData() async {
    _isLoading = true;
    notifyListeners();

    _routes = await DatabaseService.instance.getRoutes();
    _stepLogs = await DatabaseService.instance.getStepLogs();
    _measurements = await DatabaseService.instance.getRouteMeasurements();

    // 一次性迁移：旧版本路线的 refSteps 作为第一条手动测量记录（倍数 1），保证平均数语义完整
    try {
      final migrated = await DatabaseService.instance.getSetting(
        'route_measurements_migrated',
      );
      if (migrated == null && _routes.isNotEmpty) {
        final now = DateTime.now();
        for (final r in _routes) {
          final exists = _measurements.any((m) => m.routeId == r.id);
          if (exists) continue;
          final m = RouteMeasurement(
            routeId: r.id!,
            steps: r.refSteps,
            multiplier: 1.0,
            computedSteps: r.refSteps,
            measuredBy: r.measuredBy,
            createdAt: r.createdAt.isBefore(now) ? r.createdAt : now,
          );
          await DatabaseService.instance.insertRouteMeasurement(m);
          _measurements.insert(0, m);
        }
        await DatabaseService.instance.setSetting(
          'route_measurements_migrated',
          'ok',
        );
      }
    } catch (_) {}

    _isLoading = false;
    notifyListeners();
  }

  /// 创建客观路线资产，返回新路线 id（用于追加首条测量记录）
  Future<int?> addRoute(
    String name, {
    int refSteps = 2000,
    String measuredBy = '自己',
    String? description,
    bool isLocked = false,
  }) async {
    final route = RouteItem(
      name: name,
      refSteps: refSteps,
      measuredBy: measuredBy,
      description: description,
      isLocked: isLocked,
    );
    final id = await DatabaseService.instance.insertRoute(route);
    _routes.insert(
      0,
      RouteItem(
        id: id,
        name: name,
        refSteps: refSteps,
        measuredBy: measuredBy,
        description: description,
        isLocked: isLocked,
        createdAt: route.createdAt,
      ),
    );
    notifyListeners();
    return id;
  }

  /// 编辑更新客观路线资产
  Future<void> updateRoute(RouteItem route) async {
    final index = _routes.indexWhere((r) => r.id == route.id);
    if (index != -1) {
      await DatabaseService.instance.updateRoute(route);
      _routes[index] = route;
      notifyListeners();
    }
  }

  /// 新增一次测量：写入测量记录，并把路线单程步数更新为全部测量的平均
  Future<void> addMeasurement({
    required int routeId,
    required int steps,
    required double multiplier,
    String measuredBy = '自己',
  }) async {
    final computed = RouteMeasurement.computeSingleSteps(steps, multiplier);
    final m = RouteMeasurement(
      routeId: routeId,
      steps: steps,
      multiplier: multiplier,
      computedSteps: computed,
      measuredBy: measuredBy,
    );
    final id = await DatabaseService.instance.insertRouteMeasurement(m);
    _measurements.insert(0, m.copyWith(id: id));
    await _recomputeRouteSteps(routeId);
    notifyListeners();
  }

  /// 删除一条测量记录并重算平均单程步数
  Future<void> deleteMeasurement(int id) async {
    final target = _measurements.firstWhere(
      (m) => m.id == id,
      orElse: () => RouteMeasurement(
        routeId: 0,
        steps: 0,
        multiplier: 1.0,
        computedSteps: 0,
      ),
    );
    await DatabaseService.instance.deleteRouteMeasurement(id);
    _measurements.removeWhere((m) => m.id == id);
    if (target.routeId != 0) {
      await _recomputeRouteSteps(target.routeId);
    }
    notifyListeners();
  }

  /// 重算某路线的平均单程步数（四舍五入），并更新 route.refSteps
  Future<void> _recomputeRouteSteps(int routeId) async {
    final list = measurementsOf(routeId);
    if (list.isEmpty) return;
    final avg =
        (list.map((m) => m.computedSteps).reduce((a, b) => a + b) / list.length)
            .round();
    final idx = _routes.indexWhere((r) => r.id == routeId);
    if (idx == -1) return;
    final updated = _routes[idx].copyWith(refSteps: avg);
    await DatabaseService.instance.updateRoute(updated);
    _routes[idx] = updated;
  }

  /// 切换路线锁定/解锁状态
  Future<void> toggleLockRoute(int routeId) async {
    final index = _routes.indexWhere((r) => r.id == routeId);
    if (index != -1) {
      final route = _routes[index];
      final newLockState = !route.isLocked;
      await DatabaseService.instance.updateRouteLock(routeId, newLockState);
      _routes[index] = route.copyWith(isLocked: newLockState);
      notifyListeners();
    }
  }

  /// 删除某客观路线资产
  Future<bool> deleteRoute(int routeId) async {
    final index = _routes.indexWhere((r) => r.id == routeId);
    if (index != -1) {
      final route = _routes[index];
      if (route.isLocked) {
        return false;
      }
      await DatabaseService.instance.deleteRoute(routeId);
      _routes.removeAt(index);
      notifyListeners();
      return true;
    }
    return false;
  }

  /// 登记某天行走打卡日志 (结合选定成员的专属身高、体重精密换算)
  Future<void> recordStepLog({
    int? routeId,
    required String routeName,
    required String walkerName,
    required int timesCount,
    required int steps,
    required int durationMinutes,
    DateTime? targetDate,
    Member? walkerMember,
    required UserProfile fallbackProfile,
  }) async {
    // 优先使用特定成员的生理参数，缺失时回退到全局 Profile
    final double heightCm = walkerMember?.heightCm ?? fallbackProfile.heightCm;
    final double weightKg = walkerMember?.weightKg ?? fallbackProfile.weightKg;
    final String gender = walkerMember?.gender ?? fallbackProfile.gender;
    final double? customStride =
        walkerMember?.customStrideCm ?? fallbackProfile.customStrideCm;

    final strideCm =
        customStride ??
        FitnessCalculator.estimateStrideLength(
          heightCm: heightCm,
          gender: gender,
        );

    final distanceKm = FitnessCalculator.stepsToKilometers(steps, strideCm);
    final caloriesKcal = FitnessCalculator.calculateCalories(
      steps: steps,
      durationMinutes: durationMinutes,
      weightKg: weightKg,
    );

    final logTimestamp = targetDate ?? DateTime.now();

    final log = StepLog(
      routeId: routeId,
      routeName: routeName,
      walkerName: walkerName,
      timesCount: timesCount,
      steps: steps,
      durationMinutes: durationMinutes,
      distanceKm: distanceKm,
      caloriesKcal: caloriesKcal,
      timestamp: logTimestamp,
    );

    final id = await DatabaseService.instance.insertStepLog(log);
    _stepLogs.insert(
      0,
      StepLog(
        id: id,
        routeId: routeId,
        routeName: routeName,
        walkerName: walkerName,
        timesCount: timesCount,
        steps: steps,
        durationMinutes: durationMinutes,
        distanceKm: distanceKm,
        caloriesKcal: caloriesKcal,
        timestamp: logTimestamp,
      ),
    );
    notifyListeners();
  }

  Future<void> deleteStepLog(int logId) async {
    await DatabaseService.instance.deleteStepLog(logId);
    _stepLogs.removeWhere((l) => l.id == logId);
    notifyListeners();
  }

  double get totalKm =>
      _stepLogs.fold(0.0, (sum, item) => sum + item.distanceKm);
  double get totalCalories =>
      _stepLogs.fold(0.0, (sum, item) => sum + item.caloriesKcal);
  int get totalSteps => _stepLogs.fold(0, (sum, item) => sum + item.steps);

  Map<String, dynamic> getRouteStats(String routeName) {
    final logs = _stepLogs.where((l) => l.routeName == routeName).toList();
    if (logs.isEmpty) {
      return {'count': 0, 'totalKm': 0.0, 'avgSteps': 0, 'avgDuration': 0};
    }

    final totalTimes = logs.fold<int>(0, (sum, item) => sum + item.timesCount);
    final totalKm = logs.fold<double>(
      0.0,
      (sum, item) => sum + item.distanceKm,
    );
    final totalSteps = logs.fold<int>(0, (sum, item) => sum + item.steps);
    final totalDuration = logs.fold<int>(
      0,
      (sum, item) => sum + item.durationMinutes,
    );

    return {
      'count': totalTimes,
      'totalKm': totalKm,
      'avgSteps': (totalSteps / logs.length).round(),
      'avgDuration': (totalDuration / logs.length).round(),
    };
  }
}
