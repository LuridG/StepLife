import 'package:flutter/foundation.dart';
import '../domain/chore_models.dart';
import '../../../core/db/database_service.dart';

class ChoreProvider extends ChangeNotifier {
  List<Member> _members = [];
  List<ChoreItem> _choreItems = [];
  List<ChoreLog> _choreLogs = [];
  bool _isLoading = true;

  List<Member> get members => _members;
  List<ChoreItem> get choreItems => _choreItems;
  List<ChoreLog> get choreLogs => _choreLogs;
  bool get isLoading => _isLoading;

  ChoreProvider() {
    loadData();
  }

  Future<void> loadData() async {
    _isLoading = true;
    notifyListeners();

    _members = await DatabaseService.instance.getMembers();
    _choreItems = await DatabaseService.instance.getChoreItems();
    _choreLogs = await DatabaseService.instance.getChoreLogs();

    _isLoading = false;
    notifyListeners();
  }

  /// 新增统一家庭成员 (带专属体貌数据: 身高/体重/性别)
  Future<void> addMember({
    required String name,
    String gender = '男',
    double heightCm = 170.0,
    double weightKg = 65.0,
    int age = 25,
    double? customStrideCm,
    int colorValue = 0xFF6366F1,
  }) async {
    final member = Member(
      name: name,
      gender: gender,
      heightCm: heightCm,
      weightKg: weightKg,
      age: age,
      customStrideCm: customStrideCm,
      colorValue: colorValue,
    );
    final id = await DatabaseService.instance.insertMember(member);
    _members.add(Member(
      id: id,
      name: name,
      gender: gender,
      heightCm: heightCm,
      weightKg: weightKg,
      age: age,
      customStrideCm: customStrideCm,
      colorValue: colorValue,
    ));
    notifyListeners();
  }

  /// 更新现有成员的生理参数
  Future<void> updateMember(Member member) async {
    final index = _members.indexWhere((m) => m.id == member.id);
    if (index != -1) {
      await DatabaseService.instance.updateMember(member);
      _members[index] = member;
      notifyListeners();
    }
  }

  /// 根据姓名匹配成员的专属身体数据
  Member? getMemberByName(String name) {
    try {
      return _members.firstWhere((m) => m.name == name);
    } catch (_) {
      return null;
    }
  }

  Future<void> addChoreItem(
    String title, {
    String category = '日常家务',
    bool isQuantifiable = false,
    String unit = '次',
  }) async {
    final item = ChoreItem(
      title: title,
      category: category,
      isQuantifiable: isQuantifiable,
      unit: unit,
    );
    final id = await DatabaseService.instance.insertChoreItem(item);
    _choreItems.add(ChoreItem(
      id: id,
      title: title,
      category: category,
      isQuantifiable: isQuantifiable,
      unit: unit,
    ));
    notifyListeners();
  }

  Future<void> logChore({
    required ChoreItem choreItem,
    required List<Member> selectedMembers,
    String? memo,
    double? value,
    DateTime? targetDate,
  }) async {
    final memberIds = selectedMembers.map((e) => e.id!).toList();
    final memberNames = selectedMembers.map((e) => e.name).toList();
    final logTimestamp = targetDate ?? DateTime.now();

    final log = ChoreLog(
      choreId: choreItem.id!,
      choreTitle: choreItem.title,
      memberIds: memberIds,
      memberNames: memberNames,
      memo: memo,
      value: value,
      timestamp: logTimestamp,
    );

    final id = await DatabaseService.instance.insertChoreLog(log);
    _choreLogs.insert(
      0,
      ChoreLog(
        id: id,
        choreId: choreItem.id!,
        choreTitle: choreItem.title,
        memberIds: memberIds,
        memberNames: memberNames,
        memo: memo,
        value: value,
        timestamp: logTimestamp,
      ),
    );
    notifyListeners();
  }

  Future<void> deleteLog(int logId) async {
    await DatabaseService.instance.deleteChoreLog(logId);
    _choreLogs.removeWhere((l) => l.id == logId);
    notifyListeners();
  }

  List<ChoreLog> getLogsForChoreAndDate(int choreId, DateTime date) {
    return _choreLogs.where((log) {
      return log.choreId == choreId &&
          log.timestamp.year == date.year &&
          log.timestamp.month == date.month &&
          log.timestamp.day == date.day;
    }).toList();
  }

  Map<DateTime, int> getHeatmapDatasetsForChore(int choreId) {
    final Map<DateTime, int> dataset = {};
    for (final log in _choreLogs.where((l) => l.choreId == choreId)) {
      final dateOnly = DateTime(log.timestamp.year, log.timestamp.month, log.timestamp.day);
      dataset[dateOnly] = (dataset[dateOnly] ?? 0) + 1;
    }
    return dataset;
  }

  Map<String, double> getMemberContributionStats(int choreId) {
    final Map<String, double> stats = {};
    for (final log in _choreLogs.where((l) => l.choreId == choreId)) {
      final val = log.value ?? 1.0;
      for (final name in log.memberNames) {
        stats[name] = (stats[name] ?? 0.0) + val;
      }
    }
    return stats;
  }
}
