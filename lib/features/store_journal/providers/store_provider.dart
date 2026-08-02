import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../domain/store_models.dart';
import '../domain/life_templates.dart';
import '../../../core/db/database_service.dart';
import '../../../core/cache/image_migrator.dart';

class StoreProvider extends ChangeNotifier {
  List<StoreCategory> _categories = [];
  List<StoreItem> _storeItems = [];
  List<StoreLog> _storeLogs = [];
  List<StoreMenuItem> _menuItems = [];
  String _selectedCategory = '全部分类';
  String _selectedStatus = '全部状态';
  bool _isCardView = true;
  bool _isLoading = true;

  List<StoreCategory> get categories => _categories;
  List<StoreItem> get storeItems => _storeItems;
  List<StoreLog> get storeLogs => _storeLogs;
  List<StoreMenuItem> get menuItems => _menuItems;
  String get selectedCategory => _selectedCategory;
  String get selectedStatus => _selectedStatus;
  bool get isCardView => _isCardView;
  bool get isLoading => _isLoading;

  List<StoreItem> get filteredStoreItems {
    Iterable<StoreItem> result = _storeItems;
    if (_selectedCategory != '全部分类') {
      result = result.where((item) => item.category == _selectedCategory);
    }
    if (_selectedStatus != '全部状态') {
      result = result.where((item) {
        // 仅影视记录参与状态筛选
        if (LifeTemplates.matchTemplateKey(item.category) != 'movie') return true;
        final status = item.extras['status']?.toString() ?? '想看';
        return status == _selectedStatus;
      });
    }
    return result.toList();
  }

  StoreProvider() {
    loadData();
  }

  Future<void> loadData() async {
    _isLoading = true;
    notifyListeners();

    _categories = await DatabaseService.instance.getStoreCategories();
    _storeItems = await DatabaseService.instance.getStoreItems();
    _storeLogs = await DatabaseService.instance.getStoreLogs();
    _menuItems = await DatabaseService.instance.getStoreMenuItems();

    final savedMode = await DatabaseService.instance.getPreferredViewMode();
    _isCardView = (savedMode == 'card');

    _isLoading = false;
    notifyListeners();

    // 图片惰性迁移（后台复制旧相册路径 → 应用缓存，幂等）
    ImageMigrator.schedule();
  }

  Future<void> toggleViewMode() async {
    _isCardView = !_isCardView;
    notifyListeners();
    await DatabaseService.instance.savePreferredViewMode(_isCardView ? 'card' : 'list');
  }

  void selectCategory(String categoryName) {
    _selectedCategory = categoryName;
    if (_selectedStatus != '全部状态') {
      bool isMovieCat = false;
      if (categoryName == '全部分类') {
        isMovieCat = _storeItems.any((i) => LifeTemplates.matchTemplateKey(i.category) == 'movie');
      } else {
        isMovieCat = _storeItems.any((i) => i.category == categoryName && LifeTemplates.matchTemplateKey(i.category) == 'movie');
      }
      if (!isMovieCat) _selectedStatus = '全部状态';
    }
    notifyListeners();
  }

  void selectStatus(String statusName) {
    _selectedStatus = statusName;
    notifyListeners();
  }

  Future<void> addCategory(String name) async {
    final templateKey = LifeTemplates.matchTemplateKey(name);
    final cat = StoreCategory(name: name, templateKey: templateKey);
    final id = await DatabaseService.instance.insertStoreCategory(cat);
    if (id > 0) {
      _categories.add(StoreCategory(id: id, name: name, templateKey: templateKey));
      notifyListeners();
    }
  }

  Future<void> updateCategory(
    int catId,
    String newName,
    String oldName, {
    String? templateKey,
    List<Map<String, dynamic>>? extraFields,
  }) async {
    await DatabaseService.instance.updateStoreCategory(catId, newName, oldName);
    if (templateKey != null) {
      await DatabaseService.instance.updateCategoryTemplate(catId, templateKey);
    }
    if (extraFields != null) {
      await DatabaseService.instance
          .updateCategoryExtraFields(catId, jsonEncode(extraFields));
    }
    final index = _categories.indexWhere((c) => c.id == catId);
    if (index != -1) {
      _categories[index] = StoreCategory(
        id: catId,
        name: newName,
        iconName: _categories[index].iconName,
        templateKey: templateKey ?? _categories[index].templateKey,
        extraFields: extraFields ?? _categories[index].extraFields,
      );
    }
    for (int i = 0; i < _storeItems.length; i++) {
      if (_storeItems[i].category == oldName) {
        _storeItems[i] = _storeItems[i].copyWith(category: newName);
      }
    }
    if (_selectedCategory == oldName) {
      _selectedCategory = newName;
    }
    notifyListeners();
  }

  Future<void> deleteCategory(int catId, String catName) async {
    await DatabaseService.instance.deleteStoreCategory(catId, catName);
    _categories.removeWhere((c) => c.id == catId);

    for (int i = 0; i < _storeItems.length; i++) {
      if (_storeItems[i].category == catName) {
        _storeItems[i] = _storeItems[i].copyWith(category: '通用未分类');
      }
    }

    if (_selectedCategory == catName) {
      _selectedCategory = '全部分类';
    }
    notifyListeners();
  }

  Future<void> addStoreItem({
    required String name,
    required String category,
    double rating = 5.0,
    required List<String> images,
    String? address,
    String? notes,
    Map<String, dynamic> extras = const {},
    List<StoreMenuItem> menuItems = const [],
  }) async {
    final item = StoreItem(
      name: name,
      category: category,
      rating: rating,
      images: images,
      address: address,
      notes: notes,
      extras: extras,
    );

    final id = await DatabaseService.instance.insertStoreItem(item);
    _storeItems.insert(
      0,
      StoreItem(
        id: id,
        name: name,
        category: category,
        rating: rating,
        images: images,
        address: address,
        notes: notes,
        extras: extras,
        createdAt: item.createdAt,
      ),
    );
    // 餐饮菜单：新建店铺时同步写入
    if (menuItems.isNotEmpty) {
      for (final m in menuItems) {
        final mid = await DatabaseService.instance
            .insertStoreMenuItem(m.copyWith(storeId: id));
        _menuItems.add(m.copyWith(id: mid, storeId: id));
      }
    }
    notifyListeners();
  }

  Future<void> updateStoreItem(
    StoreItem item, {
    List<StoreMenuItem>? menuItems,
  }) async {
    final index = _storeItems.indexWhere((i) => i.id == item.id);
    if (index != -1) {
      await DatabaseService.instance.updateStoreItem(item);
      _storeItems[index] = item;
      if (menuItems != null && item.id != null) {
        await syncStoreMenu(item.id!, menuItems);
      }
      notifyListeners();
    }
  }

  /// 同步店铺菜单：新增的插入、修改的更新、被移除的删除（保留菜品 id 以维持历史打卡引用）
  Future<void> syncStoreMenu(int storeId, List<StoreMenuItem> drafts) async {
    final existing = getMenuItemsForStore(storeId);
    final draftIds = drafts.map((m) => m.id).whereType<int>().toSet();
    for (final old in existing) {
      if (old.id != null && !draftIds.contains(old.id)) {
        await DatabaseService.instance.deleteStoreMenuItem(old.id!);
        _menuItems.removeWhere((m) => m.id == old.id);
      }
    }
    int order = 0;
    for (final draft in drafts) {
      final item = draft.copyWith(storeId: storeId, sortOrder: order);
      order++;
      if (item.id == null) {
        final mid = await DatabaseService.instance.insertStoreMenuItem(item);
        _menuItems.add(item.copyWith(id: mid));
      } else {
        await DatabaseService.instance.updateStoreMenuItem(item);
        final i = _menuItems.indexWhere((m) => m.id == item.id);
        if (i != -1) _menuItems[i] = item;
      }
    }
  }

  Future<void> deleteStoreItem(int itemId) async {
    await DatabaseService.instance.deleteStoreItem(itemId);
    _storeItems.removeWhere((i) => i.id == itemId);
    _storeLogs.removeWhere((l) => l.storeId == itemId);
    _menuItems.removeWhere((m) => m.storeId == itemId);
    notifyListeners();
  }

  Future<void> recordStoreCheckin({
    required int storeId,
    required String storeName,
    double? cost,
    required List<int> visitorIds,
    required List<String> visitorNames,
    String? memo,
    Map<String, dynamic> extras = const {},
    List<int> menuItemIds = const [],
    List<String> menuNames = const [],
    List<String> menuSpecs = const [],
    DateTime? targetDate,
  }) async {
    final log = StoreLog(
      storeId: storeId,
      storeName: storeName,
      cost: cost,
      visitorIds: visitorIds,
      visitorNames: visitorNames,
      memo: memo,
      extras: extras,
      menuItemIds: menuItemIds,
      menuNames: menuNames,
      menuSpecs: menuSpecs,
      timestamp: targetDate ?? DateTime.now(),
    );

    final id = await DatabaseService.instance.insertStoreLog(log);
    _storeLogs.insert(
      0,
      StoreLog(
        id: id,
        storeId: storeId,
        storeName: storeName,
        cost: cost,
        visitorIds: visitorIds,
        visitorNames: visitorNames,
        memo: memo,
        extras: extras,
        menuItemIds: menuItemIds,
        menuNames: menuNames,
        menuSpecs: menuSpecs,
        timestamp: log.timestamp,
      ),
    );
    notifyListeners();
  }

  Future<void> deleteStoreLog(int logId) async {
    await DatabaseService.instance.deleteStoreLog(logId);
    _storeLogs.removeWhere((l) => l.id == logId);
    notifyListeners();
  }

  Future<void> updateStoreLog({
    required int logId,
    required int storeId,
    required String storeName,
    double? cost,
    required List<int> visitorIds,
    required List<String> visitorNames,
    String? memo,
    Map<String, dynamic> extras = const {},
    List<int> menuItemIds = const [],
    List<String> menuNames = const [],
    List<String> menuSpecs = const [],
    DateTime? targetDate,
  }) async {
    final log = StoreLog(
      id: logId,
      storeId: storeId,
      storeName: storeName,
      cost: cost,
      visitorIds: visitorIds,
      visitorNames: visitorNames,
      memo: memo,
      extras: extras,
      menuItemIds: menuItemIds,
      menuNames: menuNames,
      menuSpecs: menuSpecs,
      timestamp: targetDate ?? DateTime.now(),
    );
    await DatabaseService.instance.updateStoreLog(log);
    final i = _storeLogs.indexWhere((l) => l.id == logId);
    if (i != -1) _storeLogs[i] = log;
    notifyListeners();
  }

  /// 影视剧集观看进度累计（打卡/修改打卡时调用，delta 可为负回退）
  Future<void> applyEpisodesProgress(int storeId, int delta) async {
    if (delta == 0) return;
    final idx = _storeItems.indexWhere((i) => i.id == storeId);
    if (idx == -1) return;
    final item = _storeItems[idx];
    final current = (item.extras['watchedEpisodes'] is num)
        ? (item.extras['watchedEpisodes'] as num).toInt()
        : 0;
    final next = (current + delta).clamp(0, 1 << 30);
    final newExtras = Map<String, dynamic>.from(item.extras);
    newExtras['watchedEpisodes'] = next;
    final updated = item.copyWith(extras: newExtras);
    _storeItems[idx] = updated;
    await DatabaseService.instance.updateStoreItem(updated);
    notifyListeners();
  }

  List<StoreLog> getLogsForStore(int storeId) {
    return _storeLogs.where((l) => l.storeId == storeId).toList();
  }

  List<StoreMenuItem> getMenuItemsForStore(int storeId) {
    return _menuItems.where((m) => m.storeId == storeId).toList();
  }

  Future<void> addMenuItem(StoreMenuItem item) async {
    final id = await DatabaseService.instance.insertStoreMenuItem(item);
    _menuItems.add(item.copyWith(id: id));
    notifyListeners();
  }

  Future<void> updateMenuItem(StoreMenuItem item) async {
    await DatabaseService.instance.updateStoreMenuItem(item);
    final i = _menuItems.indexWhere((m) => m.id == item.id);
    if (i != -1) _menuItems[i] = item;
    notifyListeners();
  }

  Future<void> deleteMenuItem(int itemId) async {
    await DatabaseService.instance.deleteStoreMenuItem(itemId);
    _menuItems.removeWhere((m) => m.id == itemId);
    notifyListeners();
  }

  int getCheckinCountForStore(int storeId) {
    return _storeLogs.where((l) => l.storeId == storeId).length;
  }

  double getTotalCostForStore(int storeId) {
    final logs = getLogsForStore(storeId);
    return logs.fold(0.0, (sum, log) => sum + (log.cost ?? 0.0));
  }
}
