import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../domain/store_models.dart';
import '../domain/life_templates.dart';
import '../utils/basket_stats.dart';
import '../../../core/db/database_service.dart';
import '../../../core/cache/image_migrator.dart';

class StoreProvider extends ChangeNotifier {
  List<StoreCategory> _categories = [];
  List<StoreItem> _storeItems = [];
  List<StoreLog> _storeLogs = [];
  List<StoreMenuItem> _menuItems = [];
  String _selectedCategory = '全部分类';
  String _selectedStatus = '全部状态';
  String _selectedMediaType = '全部媒体类型';
  String _selectedGenre = '全部题材';
  String _selectedYear = '全部年份';
  String _selectedSnackTag = '全部零食分类';
  String _selectedBasketTag = '全部果蔬分类';
  String _selectedBasketTrend = '全部涨跌';
  bool _isCardView = true;
  bool _isLoading = true;

  /// 专项排序偏好：分类名 -> 排序模式（time 添加时间 / rating 星级 / checkin 打卡次数）
  static const String kSortTime = 'time';
  static const String kSortRating = 'rating';
  static const String kSortCheckin = 'checkin';
  Map<String, String> _sortPrefs = {};
  Map<String, String> _sortDirs = {};

  List<StoreCategory> get categories => _categories;
  List<StoreItem> get storeItems => _storeItems;
  List<StoreLog> get storeLogs => _storeLogs;
  List<StoreMenuItem> get menuItems => _menuItems;
  String get selectedCategory => _selectedCategory;
  String get selectedStatus => _selectedStatus;
  String get selectedMediaType => _selectedMediaType;
  String get selectedGenre => _selectedGenre;
  String get selectedYear => _selectedYear;
  String get selectedSnackTag => _selectedSnackTag;
  String get selectedBasketTag => _selectedBasketTag;
  String get selectedBasketTrend => _selectedBasketTrend;
  bool get isCardView => _isCardView;
  bool get isLoading => _isLoading;

  /// 当前分类的排序模式（未设置过则默认按添加时间）
  String get activeSortMode => _sortPrefs[_selectedCategory] ?? kSortTime;
  String get activeSortDir => _sortDirs[_selectedCategory] ?? 'desc';

  List<StoreItem> get filteredStoreItems {
    Iterable<StoreItem> result = _storeItems;
    if (_selectedCategory != '全部分类') {
      result = result.where((item) => item.category == _selectedCategory);
    }
    if (_selectedStatus != '全部状态') {
      result = result.where((item) {
        if (_templateKeyOf(item) != 'movie') return true;
        final status = item.extras['status']?.toString() ?? '想看';
        return status == _selectedStatus;
      });
    }
    if (_selectedMediaType != '全部媒体类型') {
      result = result.where((item) {
        if (_templateKeyOf(item) != 'movie') return true;
        return resolveMediaType(item.extras) == _selectedMediaType;
      });
    }
    if (_selectedGenre != '全部题材') {
      result = result.where((item) {
        if (_templateKeyOf(item) != 'movie') return true;
        return (item.extras['genre']?.toString() ?? '') == _selectedGenre;
      });
    }
    if (_selectedYear != '全部年份') {
      result = result.where((item) {
        if (_templateKeyOf(item) != 'movie') return true;
        final year = item.extras['year']?.toString() ?? '';
        if (_selectedYear == '更早') {
          return year.isNotEmpty &&
              int.tryParse(year) != null &&
              int.parse(year) < _earliestShownYear;
        }
        return year == _selectedYear;
      });
    }
    if (_selectedSnackTag != '全部零食分类') {
      result = result.where((item) {
        if (_templateKeyOf(item) != 'snack') return true;
        return (item.extras['snackTag']?.toString() ?? '') == _selectedSnackTag;
      });
    }
    if (_selectedBasketTag != '全部果蔬分类') {
      result = result.where((item) {
        if (_templateKeyOf(item) != 'basket') return true;
        return (item.extras['basketTag']?.toString() ?? '') == _selectedBasketTag;
      });
    }
    if (_selectedBasketTrend != '全部涨跌') {
      result = result.where((item) {
        if (_templateKeyOf(item) != 'basket') return true;
        final logs = getLogsForStore(item.id ?? 0);
        final dir = BasketStats.trendDirection(logs);
        return (dir ?? 'flat') == _selectedBasketTrend;
      });
    }
    final list = result.toList();
    _applySort(list);
    return list;
  }

  /// 按当前分类的排序偏好对卡片列表排序（支持顺序/逆序切换）
  void _applySort(List<StoreItem> list) {
    final desc = activeSortDir != 'asc';
    final counts = <int, int>{};
    if (activeSortMode == kSortCheckin) {
      for (final it in list) {
        counts[it.id ?? 0] = getCheckinCountForStore(it.id ?? 0);
      }
    }
    int compare(StoreItem a, StoreItem b) {
      switch (activeSortMode) {
        case kSortRating:
          return b.rating.compareTo(a.rating);
        case kSortCheckin:
          return (counts[b.id ?? 0] ?? 0).compareTo(counts[a.id ?? 0] ?? 0);
        case kSortTime:
        default:
          final c = b.createdAt.compareTo(a.createdAt);
          if (c != 0) return c;
          return (b.id ?? 0).compareTo(a.id ?? 0);
      }
    }
    list.sort((a, b) => desc ? compare(a, b) : -compare(a, b));
  }

  /// 切换某分类的排序方式（持久化到 app_settings，重启后保留）
  /// 再次点击当前排序项时切换方向：逆序 ↔ 顺序
  Future<void> setSortMode(String category, String mode) async {
    if (_sortPrefs[category] == mode) {
      _sortDirs[category] = (_sortDirs[category] ?? 'desc') == 'desc' ? 'asc' : 'desc';
    } else {
      _sortPrefs[category] = mode;
      _sortDirs[category] = 'desc';
    }
    try {
      await DatabaseService.instance
          .setSetting('storeSortPrefs', jsonEncode(_sortPrefs));
      await DatabaseService.instance
          .setSetting('storeSortDirs', jsonEncode(_sortDirs));
    } catch (_) {}
    notifyListeners();
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

    // 加载各分类的排序偏好（无则默认按添加时间）
    try {
      final prefsJson = await DatabaseService.instance.getSetting('storeSortPrefs');
      if (prefsJson != null && prefsJson.isNotEmpty) {
        final dec = jsonDecode(prefsJson);
        if (dec is Map) {
          _sortPrefs = dec.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      }
    } catch (_) {}

    try {
      final dirsJson = await DatabaseService.instance.getSetting('storeSortDirs');
      if (dirsJson != null && dirsJson.isNotEmpty) {
        final dec = jsonDecode(dirsJson);
        if (dec is Map) {
          _sortDirs = dec.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      }
    } catch (_) {}

    // 旧数据自愈：误存到其他分类的零食条目自动归位
    await _repairMisplacedSnackItems();

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
    if (_selectedStatus != '全部状态' ||
        _selectedMediaType != '全部媒体类型' ||
        _selectedGenre != '全部题材' ||
        _selectedYear != '全部年份') {
      bool isMovieCat = false;
      if (categoryName == '全部分类') {
        isMovieCat = _storeItems.any((i) => _templateKeyOf(i) == 'movie');
      } else {
        isMovieCat = _storeItems.any((i) => i.category == categoryName && _templateKeyOf(i) == 'movie');
      }
      if (!isMovieCat) {
        _selectedStatus = '全部状态';
        _selectedMediaType = '全部媒体类型';
        _selectedGenre = '全部题材';
        _selectedYear = '全部年份';
        _selectedSnackTag = '全部零食分类';
        _selectedBasketTag = '全部果蔬分类';
        _selectedBasketTrend = '全部涨跌';
      }
      if (categoryName == '全部分类' || !_storeItems.any((i) => i.category == categoryName && _templateKeyOf(i) == 'snack')) {
        _selectedSnackTag = '全部零食分类';
      }
      if (categoryName == '全部分类' || !_storeItems.any((i) => i.category == categoryName && _templateKeyOf(i) == 'basket')) {
        _selectedBasketTag = '全部果蔬分类';
        _selectedBasketTrend = '全部涨跌';
      }
    }
    notifyListeners();
  }

  void selectStatus(String statusName) {
    _selectedStatus = statusName;
    notifyListeners();
  }

  void selectMediaType(String value) {
    _selectedMediaType = value;
    notifyListeners();
  }

  void selectGenre(String value) {
    _selectedGenre = value;
    notifyListeners();
  }

  void selectYear(String value) {
    _selectedYear = value;
    notifyListeners();
  }

  void selectSnackTag(String value) {
    _selectedSnackTag = value;
    notifyListeners();
  }

  void selectBasketTag(String value) {
    _selectedBasketTag = value;
    notifyListeners();
  }

  void selectBasketTrend(String value) {
    _selectedBasketTrend = value;
    notifyListeners();
  }

  /// 年份筛选中“更早”的边界：展示年份列表里最旧的年份
  int _earliestShownYear = 9999;

  /// 设置“更早”边界（由 UI 按数据动态计算后调用）
  void setEarliestShownYear(int year) {
    _earliestShownYear = year;
  }

  Future<void> addCategory(String name, {String? templateKey}) async {
    final key = templateKey ?? LifeTemplates.matchTemplateKey(name);
    // 同名分类已存在：仅校正模板绑定，避免 UNIQUE 冲突导致静默失败
    for (final c in _categories) {
      if (c.name == name) {
        if (c.templateKey != key && c.id != null) {
          await DatabaseService.instance.updateCategoryTemplate(c.id!, key);
          _categories[_categories.indexOf(c)] = c.copyWith(templateKey: key);
          notifyListeners();
        }
        return;
      }
    }
    final cat = StoreCategory(name: name, templateKey: key);
    final id = await DatabaseService.instance.insertStoreCategory(cat);
    if (id > 0) {
      _categories.add(StoreCategory(id: id, name: name, templateKey: key));
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
    // 补卡/改时后始终按打卡时间倒序展示（新→旧），不随插入先后变化
    _storeLogs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
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
    _storeLogs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
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

  /// 按分类绑定模板解析条目模板（兜底按分类名关键词匹配）
  String _templateKeyOf(StoreItem item) {
    for (final c in _categories) {
      if (c.name == item.category) return c.templateKey;
    }
    return LifeTemplates.matchTemplateKey(item.category);
  }

  /// 旧数据自愈：历史版本画廊选模板未自动建分类，导致零食条目落错分类。
  /// 带零食专属字段（snackTag）但分类未绑定零食模板的条目，自动归入零食分类。
  Future<void> _repairMisplacedSnackItems() async {
    StoreCategory? snackCat;
    final repaired = <StoreItem>[];
    for (final item in _storeItems) {
      if ((item.extras['snackTag']?.toString() ?? '').isEmpty) continue;
      if (_templateKeyOf(item) == 'snack') continue;
      snackCat ??= _firstSnackCategory();
      if (snackCat == null) {
        await addCategory('零食干货', templateKey: 'snack');
        snackCat = _firstSnackCategory();
      }
      if (snackCat == null) continue;
      final updated = item.copyWith(category: snackCat.name);
      await DatabaseService.instance.updateStoreItem(updated);
      repaired.add(updated);
    }
    if (repaired.isEmpty) return;
    for (final r in repaired) {
      final i = _storeItems.indexWhere((x) => x.id == r.id);
      if (i != -1) _storeItems[i] = r;
    }
    notifyListeners();
  }

  StoreCategory? _firstSnackCategory() {
    for (final c in _categories) {
      if (c.templateKey == 'snack') return c;
    }
    return null;
  }

}
