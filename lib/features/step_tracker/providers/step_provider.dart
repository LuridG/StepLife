import 'package:flutter/foundation.dart';
import '../domain/step_models.dart';
import '../../profile/domain/user_profile.dart';
import '../../chore_tracker/domain/chore_models.dart';
import '../../../core/db/database_service.dart';
import '../../../core/utils/fitness_calculator.dart';

class StepProvider extends ChangeNotifier {
  List<RouteItem> _routes = [];
  List<StepLog> _stepLogs = [];
  bool _isLoading = true;

  List<RouteItem> get routes => _routes;
  List<StepLog> get stepLogs => _stepLogs;
  bool get isLoading => _isLoading;

  StepProvider() {
    loadData();
  }

  Future<void> loadData() async {
    _isLoading = true;
    notifyListeners();

    _routes = await DatabaseService.instance.getRoutes();
    _stepLogs = await DatabaseService.instance.getStepLogs();

    _isLoading = false;
    notifyListeners();
  }

  /// 创建客观路线资产
  Future<void> addRoute(
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
    final double? customStride = walkerMember?.customStrideCm ?? fallbackProfile.customStrideCm;

    final strideCm = customStride ??
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

  double get totalKm => _stepLogs.fold(0.0, (sum, item) => sum + item.distanceKm);
  double get totalCalories => _stepLogs.fold(0.0, (sum, item) => sum + item.caloriesKcal);
  int get totalSteps => _stepLogs.fold(0, (sum, item) => sum + item.steps);

  Map<String, dynamic> getRouteStats(String routeName) {
    final logs = _stepLogs.where((l) => l.routeName == routeName).toList();
    if (logs.isEmpty) {
      return {
        'count': 0,
        'totalKm': 0.0,
        'avgSteps': 0,
        'avgDuration': 0,
      };
    }

    final totalTimes = logs.fold<int>(0, (sum, item) => sum + item.timesCount);
    final totalKm = logs.fold<double>(0.0, (sum, item) => sum + item.distanceKm);
    final totalSteps = logs.fold<int>(0, (sum, item) => sum + item.steps);
    final totalDuration = logs.fold<int>(0, (sum, item) => sum + item.durationMinutes);

    return {
      'count': totalTimes,
      'totalKm': totalKm,
      'avgSteps': (totalSteps / logs.length).round(),
      'avgDuration': (totalDuration / logs.length).round(),
    };
  }
}
