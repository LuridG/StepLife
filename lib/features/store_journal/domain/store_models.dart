import 'dart:convert';

class StoreCategory {
  final int? id;
  final String name;
  final String iconName;

  /// 分类绑定的基础模板 key（movie / dining / book / place / shopping / generic）
  final String templateKey;

  /// 用户自定义字段定义（JSON 数组，元素为 TemplateField 结构）
  final List<Map<String, dynamic>> extraFields;

  StoreCategory({
    this.id,
    required this.name,
    this.iconName = 'storefront',
    this.templateKey = 'generic',
    this.extraFields = const [],
  });

  StoreCategory copyWith({
    int? id,
    String? name,
    String? iconName,
    String? templateKey,
    List<Map<String, dynamic>>? extraFields,
  }) {
    return StoreCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      iconName: iconName ?? this.iconName,
      templateKey: templateKey ?? this.templateKey,
      extraFields: extraFields ?? this.extraFields,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'iconName': iconName,
      'templateKey': templateKey,
      'extraFieldsJson': jsonEncode(extraFields),
    };
  }

  factory StoreCategory.fromMap(Map<String, dynamic> map) {
    List<Map<String, dynamic>> extra = [];
    final raw = map['extraFieldsJson'];
    if (raw != null && raw.toString().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw as String);
        if (decoded is List) {
          extra = decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } catch (_) {}
    }
    return StoreCategory(
      id: map['id'] as int?,
      name: map['name'] as String,
      iconName: map['iconName'] as String? ?? 'storefront',
      templateKey: map['templateKey'] as String? ?? 'generic',
      extraFields: extra,
    );
  }
}

class StoreItem {
  final int? id;
  final String name;
  final String category;
  final double rating;
  final List<String> images; // 至多 3 张照片/剧照/海报路径
  final String? address; // 位置/来源/平台
  final String? notes; // 特色/说明/备忘

  /// 模板专属字段值（movie 的导演/年份、dining 的招牌菜等）
  final Map<String, dynamic> extras;

  final DateTime createdAt;

  StoreItem({
    this.id,
    required this.name,
    required this.category,
    this.rating = 5.0,
    required this.images,
    this.address,
    this.notes,
    this.extras = const {},
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  StoreItem copyWith({
    int? id,
    String? name,
    String? category,
    double? rating,
    List<String>? images,
    String? address,
    String? notes,
    Map<String, dynamic>? extras,
    DateTime? createdAt,
  }) {
    return StoreItem(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      rating: rating ?? this.rating,
      images: images ?? this.images,
      address: address ?? this.address,
      notes: notes ?? this.notes,
      extras: extras ?? this.extras,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'rating': rating,
      'imagesJson': jsonEncode(images),
      'address': address,
      'notes': notes,
      'extrasJson': jsonEncode(extras),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory StoreItem.fromMap(Map<String, dynamic> map) {
    List<String> imgs = [];
    if (map['imagesJson'] != null) {
      final decoded = jsonDecode(map['imagesJson'] as String);
      if (decoded is List) {
        imgs = decoded.map((e) => e.toString()).toList();
      }
    }

    Map<String, dynamic> extras = {};
    final rawExtras = map['extrasJson'];
    if (rawExtras != null && rawExtras.toString().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawExtras as String);
        if (decoded is Map) {
          extras = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }

    return StoreItem(
      id: map['id'] as int?,
      name: map['name'] as String,
      category: map['category'] as String? ?? '通用分类',
      rating: (map['rating'] as num?)?.toDouble() ?? 5.0,
      images: imgs,
      address: map['address'] as String?,
      notes: map['notes'] as String?,
      extras: extras,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }
}

class StoreLog {
  final int? id;
  final int storeId;
  final String storeName;
  final double? cost; // 本次打卡消费
  final List<int> visitorIds; // 参与/同行成员 ID 列表
  final List<String> visitorNames; // 参与/同行成员 姓名 列表
  final String? memo; // 打卡体验心得

  /// 模板专属打卡字段值（观影渠道、点的菜、阅读进度等）
  final Map<String, dynamic> extras;

  /// 餐饮打卡：本次点选的菜品 ID 与名称（用于自动统计消费）
  final List<int> menuItemIds;
  final List<String> menuNames;

  final DateTime timestamp; // 分钟级打卡时刻 (yyyy-MM-dd HH:mm)

  StoreLog({
    this.id,
    required this.storeId,
    required this.storeName,
    this.cost,
    this.visitorIds = const [],
    this.visitorNames = const ['自己'],
    this.memo,
    this.extras = const {},
    this.menuItemIds = const [],
    this.menuNames = const [],
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  StoreLog copyWith({
    int? id,
    int? storeId,
    String? storeName,
    double? cost,
    List<int>? visitorIds,
    List<String>? visitorNames,
    String? memo,
    Map<String, dynamic>? extras,
    List<int>? menuItemIds,
    List<String>? menuNames,
    DateTime? timestamp,
  }) {
    return StoreLog(
      id: id ?? this.id,
      storeId: storeId ?? this.storeId,
      storeName: storeName ?? this.storeName,
      cost: cost ?? this.cost,
      visitorIds: visitorIds ?? this.visitorIds,
      visitorNames: visitorNames ?? this.visitorNames,
      memo: memo ?? this.memo,
      extras: extras ?? this.extras,
      menuItemIds: menuItemIds ?? this.menuItemIds,
      menuNames: menuNames ?? this.menuNames,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'storeId': storeId,
      'storeName': storeName,
      'cost': cost,
      'visitorIdsJson': jsonEncode(visitorIds),
      'visitorNamesJson': jsonEncode(visitorNames),
      'memo': memo,
      'extrasJson': jsonEncode(extras),
      'menuItemIdsJson': jsonEncode(menuItemIds),
      'menuNamesJson': jsonEncode(menuNames),
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory StoreLog.fromMap(Map<String, dynamic> map) {
    List<int> vIds = [];
    List<String> vNames = [];
    if (map['visitorIdsJson'] != null) {
      final decoded = jsonDecode(map['visitorIdsJson'] as String);
      if (decoded is List) {
        vIds = decoded.map((e) => (e as num).toInt()).toList();
      }
    }
    if (map['visitorNamesJson'] != null) {
      final decoded = jsonDecode(map['visitorNamesJson'] as String);
      if (decoded is List) {
        vNames = decoded.map((e) => e.toString()).toList();
      }
    }
    if (vNames.isEmpty && map['visitorName'] != null) {
      vNames = [map['visitorName'] as String];
    }

    Map<String, dynamic> extras = {};
    final rawExtras = map['extrasJson'];
    if (rawExtras != null && rawExtras.toString().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawExtras as String);
        if (decoded is Map) {
          extras = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }

    List<int> menuIds = [];
    if (map['menuItemIdsJson'] != null) {
      final decoded = jsonDecode(map['menuItemIdsJson'] as String);
      if (decoded is List) {
        menuIds = decoded.map((e) => (e as num).toInt()).toList();
      }
    }
    List<String> menuNames = [];
    if (map['menuNamesJson'] != null) {
      final decoded = jsonDecode(map['menuNamesJson'] as String);
      if (decoded is List) {
        menuNames = decoded.map((e) => e.toString()).toList();
      }
    }

    return StoreLog(
      id: map['id'] as int?,
      storeId: map['storeId'] as int,
      storeName: map['storeName'] as String,
      cost: (map['cost'] as num?)?.toDouble(),
      visitorIds: vIds,
      visitorNames: vNames.isNotEmpty ? vNames : ['自己'],
      memo: map['memo'] as String?,
      extras: extras,
      menuItemIds: menuIds,
      menuNames: menuNames,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}


/// 餐饮菜单条目：固定名称 + 价格，可选菜品图片（图片存入应用缓存）
class StoreMenuItem {
  final int? id;
  final int storeId;
  final String name;
  final double price;
  final String? imagePath;
  final int sortOrder;
  final DateTime createdAt;

  StoreMenuItem({
    this.id,
    this.storeId = 0,
    required this.name,
    this.price = 0,
    this.imagePath,
    this.sortOrder = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  StoreMenuItem copyWith({
    int? id,
    int? storeId,
    String? name,
    double? price,
    String? imagePath,
    int? sortOrder,
    DateTime? createdAt,
  }) {
    return StoreMenuItem(
      id: id ?? this.id,
      storeId: storeId ?? this.storeId,
      name: name ?? this.name,
      price: price ?? this.price,
      imagePath: imagePath ?? this.imagePath,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'storeId': storeId,
      'name': name,
      'price': price,
      'imagePath': imagePath,
      'sortOrder': sortOrder,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory StoreMenuItem.fromMap(Map<String, dynamic> map) {
    return StoreMenuItem(
      id: map['id'] as int?,
      storeId: (map['storeId'] as num?)?.toInt() ?? 0,
      name: map['name'] as String,
      price: (map['price'] as num?)?.toDouble() ?? 0,
      imagePath: map['imagePath'] as String?,
      sortOrder: (map['sortOrder'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.tryParse(map['createdAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}
