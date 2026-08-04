import '../../features/store_journal/domain/store_models.dart' show MenuItemSpec;

/// 导入落库策略：新建（重名自动加后缀）或合并（匹配已有项目追加打卡）
enum ImportStrategy { create, merge }

/// 单条打卡草稿（可编辑、可勾选）
class ImportLogDraft {
  ImportLogDraft({
    this.cost,
    this.timestamp,
    this.memo,
    this.visitorNames = const ['自己'],
    this.extras = const {},
    this.menuNames = const [],
    this.menuSpecs = const [],
    this.selected = true,
  });

  double? cost;
  DateTime? timestamp;
  String? memo;
  List<String> visitorNames;
  Map<String, dynamic> extras;
  List<String> menuNames;
  List<String> menuSpecs;
  bool selected;
}

/// 菜单条目草稿
class ImportMenuItemDraft {
  ImportMenuItemDraft({
    required this.name,
    this.price = 0,
    this.specs = const [],
    this.rating = 0,
    this.sortOrder = 0,
    this.selected = true,
  });

  final String name;
  final double price;
  final List<MenuItemSpec> specs;
  final int rating;
  final int sortOrder;
  bool selected;
}

/// 生活项目草稿（客观属性 + 打卡记录 + 菜单）
class ImportItemDraft {
  ImportItemDraft({
    required this.name,
    required this.category,
    this.rating = 5.0,
    this.address,
    this.notes,
    this.extras = const {},
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 原始名称（永不改动，用于重名判断）
  final String name;

  /// 原始分类名（永不改动）
  final String category;

  final double rating;
  final String? address;
  final String? notes;
  final Map<String, dynamic> extras;
  final DateTime createdAt;

  /// 解析后的分类名 / 项目名（新建重名时带「(导入)」后缀，合并时为已有名）
  String resolvedCategory = '';
  String resolvedName = '';

  ImportStrategy strategy = ImportStrategy.create;
  int? targetItemId;
  bool selected = true;

  final List<ImportLogDraft> logs = [];
  final List<ImportMenuItemDraft> menuItems = [];
}

/// 分类草稿
class ImportCategoryDraft {
  ImportCategoryDraft({
    required this.name,
    this.iconName = 'storefront',
    this.templateKey = 'generic',
    this.extraFields = const [],
  });

  final String name;
  final String iconName;
  final String templateKey;
  final List<Map<String, dynamic>> extraFields;

  String resolvedName = '';
  ImportStrategy strategy = ImportStrategy.create;
  int? targetCategoryId;
  bool selected = true;

  final List<ImportItemDraft> items = [];
}

/// 整个导入草稿（纯内存，不落库）
class ImportDraft {
  ImportDraft({this.categories = const [], this.sourceFile = ''});

  final String sourceFile;
  final List<ImportCategoryDraft> categories;

  int get totalCategories => categories.where((c) => c.selected).length;

  int get totalItems => categories
      .where((c) => c.selected)
      .expand((c) => c.items)
      .where((i) => i.selected)
      .length;

  int get totalLogs => categories
      .where((c) => c.selected)
      .expand((c) => c.items)
      .expand((i) => i.logs)
      .where((l) => l.selected)
      .length;
}
