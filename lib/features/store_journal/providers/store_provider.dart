import 'package:flutter/foundation.dart';
import '../domain/store_models.dart';
import '../../../core/db/database_service.dart';

class StoreProvider extends ChangeNotifier {
  List<StoreCategory> _categories = [];
  List<StoreItem> _storeItems = [];
  List<StoreLog> _storeLogs = [];
  String _selectedCategory = '全部分类';
  bool _isCardView = true;
  bool _isLoading = true;

  List<StoreCategory> get categories => _categories;
  List<StoreItem> get storeItems => _storeItems;
  List<StoreLog> get storeLogs => _storeLogs;
  String get selectedCategory => _selectedCategory;
  bool get isCardView => _isCardView;
  bool get isLoading => _isLoading;

  List<StoreItem> get filteredStoreItems {
    if (_selectedCategory == '全部分类') {
      return _storeItems;
    }
    return _storeItems.where((item) => item.category == _selectedCategory).toList();
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

    final savedMode = await DatabaseService.instance.getPreferredViewMode();
    _isCardView = (savedMode == 'card');

    _isLoading = false;
    notifyListeners();
  }

  Future<void> toggleViewMode() async {
    _isCardView = !_isCardView;
    notifyListeners();
    await DatabaseService.instance.savePreferredViewMode(_isCardView ? 'card' : 'list');
  }

  void selectCategory(String categoryName) {
    _selectedCategory = categoryName;
    notifyListeners();
  }

  Future<void> addCategory(String name) async {
    final cat = StoreCategory(name: name);
    final id = await DatabaseService.instance.insertStoreCategory(cat);
    if (id > 0) {
      _categories.add(StoreCategory(id: id, name: name));
      notifyListeners();
    }
  }

  Future<void> updateCategory(int catId, String newName, String oldName) async {
    await DatabaseService.instance.updateStoreCategory(catId, newName, oldName);
    final index = _categories.indexWhere((c) => c.id == catId);
    if (index != -1) {
      _categories[index] = StoreCategory(id: catId, name: newName, iconName: _categories[index].iconName);
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
  }) async {
    final item = StoreItem(
      name: name,
      category: category,
      rating: rating,
      images: images,
      address: address,
      notes: notes,
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
        createdAt: item.createdAt,
      ),
    );
    notifyListeners();
  }

  Future<void> updateStoreItem(StoreItem item) async {
    final index = _storeItems.indexWhere((i) => i.id == item.id);
    if (index != -1) {
      await DatabaseService.instance.updateStoreItem(item);
      _storeItems[index] = item;
      notifyListeners();
    }
  }

  Future<void> deleteStoreItem(int itemId) async {
    await DatabaseService.instance.deleteStoreItem(itemId);
    _storeItems.removeWhere((i) => i.id == itemId);
    _storeLogs.removeWhere((l) => l.storeId == itemId);
    notifyListeners();
  }

  Future<void> recordStoreCheckin({
    required int storeId,
    required String storeName,
    double? cost,
    required List<int> visitorIds,
    required List<String> visitorNames,
    String? memo,
    DateTime? targetDate,
  }) async {
    final log = StoreLog(
      storeId: storeId,
      storeName: storeName,
      cost: cost,
      visitorIds: visitorIds,
      visitorNames: visitorNames,
      memo: memo,
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

  List<StoreLog> getLogsForStore(int storeId) {
    return _storeLogs.where((l) => l.storeId == storeId).toList();
  }

  int getCheckinCountForStore(int storeId) {
    return _storeLogs.where((l) => l.storeId == storeId).length;
  }

  double getTotalCostForStore(int storeId) {
    final logs = getLogsForStore(storeId);
    return logs.fold(0.0, (sum, log) => sum + (log.cost ?? 0.0));
  }
}
